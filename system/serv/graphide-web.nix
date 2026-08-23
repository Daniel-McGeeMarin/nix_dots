# Graphide marketing site — the static website container on :3003, plus
# website-api, a small Go service on :8010 that serves /api on both graphide.net
# and graphide.dev.
#
# == New system setup checklist ==
#
# 1. Secrets — one age-encrypted file in secrets/:
#
#    secrets/website-api-env.age  (edit with: agenix -e secrets/website-api-env.age)
#      DATABASE_URL=postgres://postgres.<ref>:<password>@<region>.pooler.supabase.com:5432/postgres
#                                  # Supabase, NOT the local cluster in
#                                  # graphide.nix. The survey data is the one
#                                  # thing here we cannot lose to a dead disk,
#                                  # and store.go is written against the
#                                  # pooler's session limits. Taking this from
#                                  # Supabase's dashboard under Connect >
#                                  # Session pooler gets the right host.
#      PORT=8010                   # must match every upstream in this file
#      DISCORD_WEBHOOK_URL=https://discord.com/api/webhooks/<id>/<token>
#      DEMO_BOXES=demobox1,demobox2,demobox3
#                                  # keep in sync with serv.graphide-demo.sessions
#      DEMO_BASE_PORT=8100         # keep in sync with serv.graphide-demo.basePort;
#                                  # box N is at DEMO_BASE_PORT + N
#      DEMO_IDLE_GRACE=5m          # how long a box stays claimed after its last
#                                  # ESTABLISHED connection goes away, so a
#                                  # page reload does not hand the box to
#                                  # somebody else mid-session. Parsed by Go's
#                                  # time.ParseDuration, so the unit is not
#                                  # optional: a bare `300` is a startup error,
#                                  # not five minutes.
#      ADMIN_GROUP=admins          # Authelia group allowed past the demo gate
#                                  # regardless of who else holds the box
#
#    Must be encrypted to the target host's SSH key, which means registering the
#    path in secrets.nix *before* running agenix -e. Until the file exists, this
#    host evaluates and builds fine and then dies in activation, when agenix
#    tries to decrypt a path that is not there — so `nix build` proving green
#    says nothing about whether the switch will land. The same omission left
#    XiaServer undeployable for a while; see the finance secrets in apps.nix.
#
# 2. GHCR image — ghcr.io/graphidehq/website-api:latest, like every other
#    graphide image, is PRIVATE. The credentials come from
#    graphide-ghcr-login.service in graphide.nix; see the ordering note below.
#    Both images are built and pushed by CI and pulled by the
#    podman-auto-update timer in apps.nix every five minutes.
#
# 3. Enable — set serv.graphide-web.enable = true in the host's
#    configuration.nix. serv.graphide.enable and serv.auth.enable must be on
#    too; see the assertions.
#
# == Key design decisions and gotchas ==
#
# - website-api runs on host networking, which is load-bearing rather than
#   incidental — see the comment on the container.
#
# - The Authelia access_control rules for the apex live here rather than in
#   auth.nix because this module is what puts `import require_auth` on the
#   apex. Adding one without the other is a lockout; see the comment on the
#   rules for the merge-order reasoning.

{ config, lib, ... }:
{
  options.serv.graphide-web.enable = lib.mkEnableOption "Graphide marketing site";

  config = lib.mkIf config.serv.graphide-web.enable {
    assertions = [
      {
        assertion = config.serv.graphide.enable;
        message = ''
          serv.graphide-web requires serv.graphide.enable — both images are in
          the private GHCR registry and graphide-ghcr-login.service, which the
          containers here order themselves behind, is defined in graphide.nix.
          Without it the `requires` below points at a unit that does not exist
          and both containers fail to start.
        '';
      }
      {
        assertion = config.serv.auth.enable;
        message = ''
          serv.graphide-web requires serv.auth.enable — the feedback-results
          routes below `import require_auth`, a Caddy snippet defined in
          auth.nix, and an undefined snippet is a Caddy config parse error that
          takes down every other vhost with it.
        '';
      }
    ];

    # Read by the website-api container. Contents are documented in the
    # checklist at the top of this file.
    age.secrets.website-api-env = {
      file = ../../secrets/website-api-env.age;
      mode = "0400";
    };

    virtualisation.oci-containers.containers = {
      graphide-web = {
        image  = "ghcr.io/graphidehq/website:latest";
        ports  = [ "127.0.0.1:3003:80" ];
        labels."io.containers.autoupdate" = "registry";
      };

      website-api = {
        image = "ghcr.io/graphidehq/website-api:latest";
        # Host networking is REQUIRED here, not laziness — do not "fix" this to
        # a published port like the containers above.
        #
        # The demo gate (/api/demo/gate, wired up in graphide-demo.nix) decides
        # whether a demo pod already has a live session by counting ESTABLISHED
        # TCP connections on the pods' host ports (8100-8102) in /proc/net/tcp.
        # A container in its own network namespace gets its own /proc/net/tcp
        # showing only its own sockets, so the count would always be zero and
        # the gate would wave everybody through onto the same box. Only the host
        # network namespace can see those connections.
        #
        # The consequence is that PORT from the env file is what binds :8010 on
        # the host; there is no `ports` mapping to override it. Keep PORT=8010
        # and the Caddy upstreams below in agreement.
        extraOptions = [ "--network=host" ];
        environmentFiles = [ config.age.secrets.website-api-env.path ];
        labels."io.containers.autoupdate" = "registry";
      };
    };

    # Both images are private, so both containers must not start before
    # `podman login ghcr.io` has run. graphide-web went without this ordering
    # for a long time and appeared to work: the login is global to root's
    # containers/auth.json, it persists across reboots, and on a normal boot it
    # usually wins the race anyway. It is still a race — a first boot, a wiped
    # auth.json or a slow agenix means the pull 401s and the container lands in
    # a restart loop. graphide-demo.nix already orders its pods this way; this
    # brings the other two into line.
    #
    # `requires` in addition to `after` so a failed login fails the containers
    # loudly instead of letting them start and 401 on the pull.
    systemd.services = {
      "podman-graphide-web" = {
        after    = [ "graphide-ghcr-login.service" ];
        requires = [ "graphide-ghcr-login.service" ];
      };
      "podman-website-api" = {
        after    = [ "graphide-ghcr-login.service" ];
        requires = [ "graphide-ghcr-login.service" ];
      };
    };

    # graphide.net goes through Caddy rather than having the tunnel point
    # straight at :3003. The demo pods need a *.graphide.net wildcard on :80,
    # and a wildcard plus a more specific tunnel rule is order-dependent in a
    # way that silently swallowed the apex once already. One ingress rule to
    # Caddy for the whole zone keeps the routing in this file instead.
    #
    # Both apexes are split into `handle` blocks so /api can reach website-api
    # while everything else still reaches the static site. handle blocks are
    # mutually exclusive and evaluated in the order written, so the specific
    # paths MUST come before the catch-all — the same shape as the
    # mcgeedan.com vhost in apps.nix. Getting this backwards does not error;
    # the catch-all just silently eats /api and the survey posts 404 against
    # the static site.
    #
    # graphide.dev is kept identical to graphide.net on purpose. It served the
    # same container before this change and the two drifting apart is how one
    # of them ends up with an unprotected results page.
    services.caddy.virtualHosts = let
      # The private admin views: the rendered results page comes from the static
      # site, the data behind it from website-api. Both need the same gate, or
      # the page is protected and the JSON it fetches is not.
      graphideSite = ''
        handle /api/feedback/results* {
          import require_auth
          reverse_proxy 127.0.0.1:8010 {
            header_up X-Forwarded-Proto https
          }
        }
        handle /feedback/results* {
          import require_auth
          reverse_proxy 127.0.0.1:3003 {
            header_up X-Forwarded-Proto https
          }
        }
        # Admin force-release of a stuck demo box. It needs its own gated block
        # rather than relying on the API's own check, because that check reads
        # Remote-Groups and the block below is reachable by anyone: without this
        # block, `curl -H 'Remote-Groups: <admin group>' .../api/demo/release`
        # evicts whoever is on a box.
        #
        # What defeats the forgery is copy_headers in the require_auth snippet:
        # it sets the four Remote-* headers from Authelia's response, and when
        # that response omits one it blanks it rather than passing the caller's
        # through. So this block fails closed even on a bypass. It only
        # *functions* because the access_control rule below names this path, which
        # is what makes Authelia authenticate and fill the header in.
        handle /api/demo/release* {
          import require_auth
          reverse_proxy 127.0.0.1:8010 {
            header_up X-Forwarded-Proto https
          }
        }
        # Public on purpose — this is where survey and feedback submissions
        # land, from visitors who have no account and never will.
        #
        # The Remote-* headers are deleted on the way in. website-api derives
        # identity and admin status from them (isAdmin in api/server.go), and on
        # this block nothing upstream has authenticated the caller, so anything
        # they send is a claim about themselves. Deleting them means the API sees
        # no identity at all here, which is what it should see. The routes that
        # legitimately carry these headers are unaffected: /api/feedback/results
        # above gets them from Authelia, and the demo-box gate is called by
        # forward_auth straight to 127.0.0.1:8010 from the vhosts in
        # graphide-demo.nix, never through this block.
        handle /api/* {
          reverse_proxy 127.0.0.1:8010 {
            header_up X-Forwarded-Proto https
            header_up -Remote-User
            header_up -Remote-Groups
            header_up -Remote-Name
            header_up -Remote-Email
          }
        }
        handle {
          reverse_proxy 127.0.0.1:3003 {
            header_up X-Forwarded-Proto https
          }
        }
      '';
    in {
      "http://graphide.dev".extraConfig = graphideSite;
      "http://www.graphide.dev".extraConfig = ''
        redir https://graphide.dev{uri} permanent
      '';
      "http://graphide.net".extraConfig = graphideSite;
      "http://www.graphide.net".extraConfig = ''
        redir https://graphide.net{uri} permanent
      '';
    };

    # Authelia's default_policy is deny, and until now NOTHING on the apex ever
    # called forward_auth, so the total absence of a rule for graphide.net was
    # invisible. The `import require_auth` above changes that: Authelia is now
    # consulted for the results paths, and a request that matches no rule falls
    # through to the default deny — which would lock out admins too, since deny
    # is deny for everybody. These rules are the other half of that change and
    # must not be separated from it.
    #
    # Where this lands in the merged list: NixOS concatenates list definitions
    # in priority order (mkBefore = 500, plain = 1000, mkAfter = 1500).
    # auth.nix defines the base rules plainly; graphide-demo.nix defines the
    # auth.graphide.net bypass and the per-pod rules with lib.mkBefore. This
    # definition is deliberately left at the default priority so it can never
    # get in front of the demo-pod gate and weaken it. The merged order comes
    # out as:
    #
    #   1. auth.graphide.net bypass + demobox1..3   (graphide-demo.nix, mkBefore)
    #   2. these four rules                          (here, default priority)
    #   3. auth.mcgeedan.com .. *.mcgeedan.com       (auth.nix, default priority)
    #
    # Position relative to block 3 is immaterial either way: Authelia matches
    # `domain` exactly unless it is a wildcard, so no mcgeedan rule — not even
    # `*.mcgeedan.com` — can match a graphide domain. Likewise a bare
    # `graphide.net` here does not match `demoboxN.graphide.net`, so block 1
    # keeps its own rules regardless.
    #
    # What genuinely matters is the order *within* this list: a bypass for the
    # whole domain placed before the resource rule would make the results pages
    # public, and Authelia takes the first matching rule.
    #
    # subject = group:admins rather than a bare one_factor: an unscoped rule
    # admits any authenticated user, and demo guests have accounts in the same
    # Authelia — see the same argument spelled out in auth.nix.
    #
    # CAVEAT for graphide.dev: session.cookies has entries for mcgeedan.com and
    # graphide.net only, so Authelia has no session domain covering
    # graphide.dev and cannot issue it a cookie. The bypass rule is unaffected
    # (a bypass never needs a session), but the two results paths on
    # graphide.dev will 401 rather than redirect to a login portal until
    # graphide.dev gets its own session cookie domain and an auth.graphide.dev
    # portal vhost. That is a deliberate fail-closed: those paths are currently
    # served to anyone who asks.
    # /api/demo/release is in `resources` for a functional reason rather than a
    # security one. The Caddy block for it imports require_auth, but a path not
    # listed here falls through to the domain-wide bypass below, and on a bypass
    # Authelia authenticates nobody and returns no Remote-* headers. Caddy's
    # copy_headers blanks the headers it is told to copy when the auth response
    # omits them — verified against a stub that echoes what arrived, so a forged
    # Remote-Groups does not survive a bypass either — which means the endpoint
    # was secure and simultaneously dead: isAdmin saw an empty group list and
    # returned 403 to real admins too. Naming the path here is what makes
    # Authelia actually authenticate and populate the header.
    services.authelia.instances.main.settings.access_control.rules = [
      { domain = "graphide.net";
        resources = [ "^/feedback/results(/.*)?$" "^/api/feedback/results(/.*)?$" "^/api/demo/release(/.*)?$" ];
        policy = "one_factor";
        subject = [ "group:admins" ]; }
      { domain = "graphide.net"; policy = "bypass"; }
      { domain = "graphide.dev";
        resources = [ "^/feedback/results(/.*)?$" "^/api/feedback/results(/.*)?$" "^/api/demo/release(/.*)?$" ];
        policy = "one_factor";
        subject = [ "group:admins" ]; }
      { domain = "graphide.dev"; policy = "bypass"; }
    ];
  };
}
