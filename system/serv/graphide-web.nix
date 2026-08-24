# Graphide marketing site — the static website container on :3003, plus
# website-api, a small Go service on :8010 that serves /api on both graphide.net
# and graphide.dev.
#
# == New system setup checklist ==
#
# 1. Secrets — one age-encrypted file in secrets/:
#
#    This file is read by podman as an --env-file, so it is KEY=value lines and
#    nothing else. That is worth stating because the one mistake made here was
#    pasting Supabase's connection URI on its own, with no DATABASE_URL= in
#    front of it: podman finds no `=`, sets no variable, and the API dies with
#    "DATABASE_URL is required" while the file plainly contains the URL. Three
#    further traps in the same layer, all invisible on inspection — podman does
#    not strip surrounding quotes, so "..." ends up inside the value; spaces
#    around the = become part of the key name; and CRLF endings append a \r to
#    the value.
#
#    Only DATABASE_URL is actually required. Every other setting below already
#    defaults, in config.go, to the value this host wants, so the shortest
#    correct file is that one line. They are documented because overriding them
#    means keeping them in step with the Caddy upstreams and the demo module.
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
#      PORT=8010                   # optional, and 8010 is already the default.
#                                  # Must match every upstream in this file.
#      DISCORD_WEBHOOK_URL=https://discord.com/api/webhooks/<id>/<token>
#                                  # optional; unset means no Discord notice on
#                                  # a new response or signup, nothing more.
#      DEMO_BOXES=demobox1,demobox2,demobox3
#                                  # optional, and this is the default. Keep in
#                                  # sync with serv.graphide-demo.sessions.
#      DEMO_BASE_PORT=8100         # optional, and this is the default. Keep in
#                                  # sync with serv.graphide-demo.basePort.
#                                  # Ports go by list position from zero, so
#                                  # the FIRST box is at DEMO_BASE_PORT itself:
#                                  # demobox1 is 8100, not 8101. Both this and
#                                  # graphide-demo.nix index from zero, so they
#                                  # agree, but the arithmetic is off by one
#                                  # from the box names.
#      DEMO_IDLE_GRACE=5m          # optional, and this is the default. How long
#                                  # a box stays claimed after its last
#                                  # ESTABLISHED connection goes away, so a
#                                  # page reload does not hand the box to
#                                  # somebody else mid-session. Parsed by Go's
#                                  # time.ParseDuration, so the unit is not
#                                  # optional: a bare `300` is a startup error,
#                                  # not five minutes.
#      ADMIN_GROUP=admins          # optional, and this is the default. Authelia
#                                  # group allowed past the demo gate
#                                  # regardless of who else holds the box.
#
#    Must be encrypted to the target host's SSH key, which means registering the
#    path in secrets.nix *before* running agenix -e. Until the file exists, this
#    host evaluates and builds fine and then dies in activation, when agenix
#    tries to decrypt a path that is not there — so `nix build` proving green
#    says nothing about whether the switch will land. The same omission left
#    XiaServer undeployable for a while; see the finance secrets in apps.nix.
#
# 2. Images — one of two ways, and they are mutually exclusive:
#
#    a. GHCR (the default). ghcr.io/graphidehq/website:latest and
#       ...website-api:latest, both PRIVATE. Credentials come from
#       graphide-ghcr-login.service in graphide.nix; see the ordering note
#       below. CI builds and pushes them; the podman-auto-update timer in
#       apps.nix pulls every five minutes.
#
#       The failure mode worth knowing: CI is the only publisher, so when the
#       account's GitHub Actions minutes run out nothing gets pushed, and the
#       box reports `manifest unknown`. That reads like a bad tag or bad
#       credentials, but it means the tag genuinely is not there. This is what
#       left graphide.net serving a month-old build while every unit here
#       looked healthy except one.
#
#    b. autoBuild — clone the repo and build both images on this box, as
#       graphide-demo already does for the pods. Needs no Actions minutes and
#       no registry, so it survives (a)'s failure mode. Set:
#
#         serv.graphide-web.autoBuild.enable = true;
#         serv.graphide-web.image      = "localhost/website:latest";
#         serv.graphide-web.apiImage   = "localhost/website-api:latest";
#         serv.graphide-web.autoUpdate = false;
#
#       The clone needs a token for the private repo. By default it borrows the
#       PAT graphide-demo.nix declares, which must be re-scoped in GitHub to
#       include the website repo — re-scoping does not change the token, so the
#       .age file stays as is. Assertions below catch both mistakes.
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

{ config, lib, pkgs, ... }:
let
  cfg = config.serv.graphide-web;
in
{
  options.serv.graphide-web = {
    enable = lib.mkEnableOption "Graphide marketing site";

    image = lib.mkOption {
      type = lib.types.str;
      default = "ghcr.io/graphidehq/website:latest";
      description = "Static site image. Set to a localhost/ tag when autoBuild is on.";
    };

    apiImage = lib.mkOption {
      type = lib.types.str;
      default = "ghcr.io/graphidehq/website-api:latest";
      description = "website-api image. Set to a localhost/ tag when autoBuild is on.";
    };

    autoUpdate = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Label both containers for podman-auto-update. Must be false for a
        localhost/ tag: auto-update pulls, and there is no registry to pull a
        local tag from, so it fails on every timer tick.
      '';
    };

    # Deliberately the same shape as serv.graphide-demo.autoBuild. The demo pods
    # already solved this problem and the two should read alike.
    autoBuild = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Poll the website repo and build both images on this host, instead of
          pulling them from GHCR.

          This exists because the GHCR path has a single point of failure that
          is not technical: CI publishes the images, and when the account's
          Actions minutes run out nothing publishes. The failure then looks
          like `manifest unknown` on the box, which reads as a broken tag or
          bad credentials rather than an exhausted quota. Building here wants
          no Actions minutes and no registry.

          The cost is the same one graphide-demo accepts: nothing gates the
          build, so a broken commit becomes a broken site. Both images are
          staged and promoted only if both succeed, so a failure leaves what is
          running alone rather than half-updating the pair.

          Implies local images, so set image/apiImage/autoUpdate accordingly.
        '';
      };

      interval = lib.mkOption {
        type = lib.types.str;
        default = "*:0/5";
        description = "systemd OnCalendar expression. Default is every 5 minutes.";
      };

      repoUrl = lib.mkOption {
        type = lib.types.str;
        default = "https://github.com/GraphideHQ/website.git";
      };

      branch = lib.mkOption {
        type = lib.types.str;
        default = "main";
        description = "Unlike monolith, this repo's default branch is main.";
      };

      tokenFile = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        description = ''
          File holding a GitHub token able to clone the website repo, which is
          private. Defaults to the token graphide-demo.nix already declares for
          its own autoBuild, so enabling this needs no new secret — but that
          PAT is fine-grained and scoped to monolith and gred only, so it must
          be re-scoped to include the website repo. Re-scoping a fine-grained
          PAT does not change its value, so the existing .age file stays valid
          and nothing needs re-encrypting.

          Set this to another path to supply a separate token instead.
        '';
      };

      srcDir = lib.mkOption {
        type = lib.types.path;
        default = "/srv/data/website/src";
      };
    };
  };

  config = lib.mkIf cfg.enable {
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
      {
        assertion = !cfg.autoBuild.enable
                    || cfg.autoBuild.tokenFile != null
                    || config.serv.graphide-demo.autoBuild.enable;
        message = ''
          serv.graphide-web.autoBuild needs a GitHub token to clone the private
          website repo. With tokenFile unset it borrows the one
          graphide-demo.nix declares, and that module only declares it when its
          own autoBuild is on — so as written the secret does not exist and
          activation will fail on a missing decryption target.

          Either set serv.graphide-demo.autoBuild.enable = true, or point
          serv.graphide-web.autoBuild.tokenFile at your own token file.

          Note also that the borrowed PAT is fine-grained and scoped to
          monolith and gred. It must be re-scoped in GitHub to include the
          website repo, or the clone 404s as though the branch were gone.
          Re-scoping does not change the token value, so the .age file does not
          need re-encrypting.
        '';
      }
      {
        assertion = !cfg.autoBuild.enable || !cfg.autoUpdate;
        message = ''
          serv.graphide-web has autoBuild and autoUpdate on together. Those
          contradict: autoBuild produces a localhost/ tag and autoUpdate asks
          podman-auto-update to pull it from a registry that does not have it,
          which fails on every timer tick. Set autoUpdate = false, as
          serv.graphide-demo does.
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
        image  = cfg.image;
        ports  = [ "127.0.0.1:3003:80" ];
        labels = lib.optionalAttrs cfg.autoUpdate {
          "io.containers.autoupdate" = "registry";
        };
      };

      website-api = {
        image = cfg.apiImage;
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
        labels = lib.optionalAttrs cfg.autoUpdate {
          "io.containers.autoupdate" = "registry";
        };
      };
    };

    systemd.services = lib.mkMerge [
      # Both GHCR images are private, so neither container may start before
      # `podman login ghcr.io` has run. graphide-web went without this ordering
      # for a long time and appeared to work: the login is global to root's
      # containers/auth.json, it persists across reboots, and on a normal boot it
      # usually wins the race anyway. It is still a race — a first boot, a wiped
      # auth.json or a slow agenix means the pull 401s and the container lands in
      # a restart loop.
      #
      # `requires` in addition to `after` so a failed login fails the containers
      # loudly instead of letting them start and 401 on the pull.
      #
      # Dropped entirely under autoBuild: a localhost/ tag is not pulled, so
      # requiring the login would make a registry credential a hard dependency
      # of containers that never contact a registry — which is the coupling
      # autoBuild exists to remove.
      (lib.mkIf (!cfg.autoBuild.enable) {
        "podman-graphide-web" = {
          after    = [ "graphide-ghcr-login.service" ];
          requires = [ "graphide-ghcr-login.service" ];
        };
        "podman-website-api" = {
          after    = [ "graphide-ghcr-login.service" ];
          requires = [ "graphide-ghcr-login.service" ];
        };
      })

      (lib.mkIf cfg.autoBuild.enable {
        website-autobuild = {
          description = "Rebuild the Graphide website images when the repo changes";
          after = [ "network-online.target" ];
          wants = [ "network-online.target" ];
          # A systemd unit's PATH is only what is listed here. gnutar/gzip
          # because podman shells out to them while assembling the build
          # context; the rest because the script and the Dockerfiles use them.
          path = [
            pkgs.bash
            pkgs.git
            pkgs.podman
            pkgs.coreutils
            pkgs.gnutar
            pkgs.gzip
            pkgs.gnugrep
            pkgs.gnused
            pkgs.findutils
            pkgs.systemd
          ];
          serviceConfig = {
            Type = "oneshot";
            # npm install plus a Go build from cold caches. Must not be killed
            # halfway by the next timer tick.
            TimeoutStartSec = "60min";
          };
          script = let
            src = "${cfg.autoBuild.srcDir}";
            tok = if cfg.autoBuild.tokenFile != null
                  then toString cfg.autoBuild.tokenFile
                  else config.age.secrets.graphide-demo-token.path;
          in ''
            set -euo pipefail

            # Same credential shape as graphide-demo's autobuild, and for the
            # same reason: git wants base64("x-access-token:<token>") rather
            # than a bare token, and `http.extraheader=@<file>` sends the
            # literal string "@/path" instead of reading the file. A malformed
            # header does not fail loudly — GitHub ignores it and falls back to
            # anonymous, which on a private repo is a 404 that reads like a
            # deleted branch.
            export GIT_CONFIG_COUNT=1
            export GIT_CONFIG_KEY_0=http.extraheader
            export GIT_CONFIG_VALUE_0="Authorization: Basic $(printf 'x-access-token:%s' "$(cat ${tok})" | base64 -w0)"
            # No TTY on a systemd service: without this a bad token hangs on an
            # interactive prompt that can never be answered.
            export GIT_TERMINAL_PROMPT=0

            mkdir -p ${src}
            dir=${src}/website
            branch=${cfg.autoBuild.branch}

            if [ ! -d "$dir/.git" ]; then
              echo "cloning ${cfg.autoBuild.repoUrl}"
              git clone --branch "$branch" ${cfg.autoBuild.repoUrl} "$dir"
            else
              git -C "$dir" fetch --quiet origin "$branch"
              git -C "$dir" checkout --quiet -B "$branch" "origin/$branch"
            fi
            current=$(git -C "$dir" rev-parse HEAD)

            stamp=${src}/.last-built
            if [ -f "$stamp" ] && [ "$(cat "$stamp")" = "$current" ]; then
              echo "no change since last build ($current)"
              exit 0
            fi

            echo "building $current"
            # Build both to staging tags first and promote only once BOTH have
            # succeeded. The site and the API are one deployment: the survey
            # page posts to /api/feedback, so shipping a new page against an
            # old API, or the reverse, is worse than shipping neither. set -e
            # means a failed build never reaches the promotion below.
            podman build -t localhost/website:building       -f "$dir/Dockerfile"     "$dir"
            podman build -t localhost/website-api:building   -f "$dir/api/Dockerfile" "$dir/api"

            podman tag localhost/website:building     ${cfg.image}
            podman tag localhost/website-api:building ${cfg.apiImage}
            echo "$current" > "$stamp"

            # reset-failed first: a unit sitting in failed state from an earlier
            # `manifest unknown` will not come back on a plain restart.
            systemctl reset-failed podman-graphide-web.service podman-website-api.service || true
            systemctl restart podman-graphide-web.service || true
            systemctl restart podman-website-api.service || true
            echo "rebuilt and restarted at $current"
          '';
        };
      })
    ];

    systemd.timers = lib.mkIf cfg.autoBuild.enable {
      website-autobuild = {
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnCalendar = cfg.autoBuild.interval;
          Persistent = true;
          RandomizedDelaySec = "60";
        };
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
