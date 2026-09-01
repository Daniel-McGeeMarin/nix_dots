{ config, lib, ... }:
# ============================================================================
# THE ONE REMAINING DEPENDENCY ON system/serv
# ----------------------------------------------------------------------------
# Everything else in this tree stands alone. This file does not: it points at
# the Authelia instance declared in system/serv/auth.nix, so the host must keep
# `serv.auth.enable = true` even when the rest of the estate is switched off.
#
# That is deliberate and it is confined to this one file, so the cost of cutting
# it later is known rather than discovered. When it is cut, it goes in two
# unequal halves:
#
#   - The demo boxes leave first. Authelia cannot issue a magic link -- a signed
#     URL that logs a guest straight in and is good for exactly one box -- and
#     that is the product requirement. They move to a signed-token gate served
#     by website-api, at which point `demoRules` and `demoSnippetUsers` below
#     disappear.
#   - The admin pages stay. /feedback/results and friends are for one person and
#     a login portal is the right shape for them, so they keep using Authelia
#     until the Graphide stack moves to a machine of its own.
# ============================================================================
let
  cfg = config.graphide.auth;
  demo = config.graphide.demo;

  # Sessions are named after their subdomain, so this is also the list of hosts
  # that need a per-box rule.
  boxRules = map (name: {
    domain = "${name}.${demo.domain}";
    policy = "one_factor";
    # Scoped to groups rather than a bare one_factor. An unscoped rule admits
    # ANY authenticated user, and demo guests have accounts in this same
    # Authelia -- so without this, inviting a guest to a pod would also hand
    # them the private journal and the finance app.
    subject = map (g: "group:${g}") demo.allowedGroups;
  }) demo.sessions;

  # The private admin views. The rendered page comes from the static site and
  # the data behind it from website-api, so both need the same gate or the page
  # is protected and the JSON it fetches is not.
  #
  # /api/demo/release is named here for a functional reason rather than a
  # security one: a path not listed falls through to the domain-wide bypass
  # below, and on a bypass Authelia authenticates nobody and returns no Remote-*
  # headers. Caddy's copy_headers blanks the headers it is told to copy when the
  # auth response omits them, so the endpoint was simultaneously secure and dead
  # -- the API's admin check saw an empty group list and 403'd real admins too.
  adminResources = [
    "^/feedback/results(/.*)?$"
    "^/api/feedback/results(/.*)?$"
    "^/api/demo/release(/.*)?$"
  ];

  apexRules = lib.concatMap (domain: [
    { inherit domain; resources = adminResources; policy = "one_factor"; subject = [ "group:admins" ]; }
    # Everything else on the marketing site is public: this is where survey and
    # feedback submissions land, from visitors who have no account and never
    # will.
    { inherit domain; policy = "bypass"; }
  ]) cfg.apexDomains;
in
{
  options.graphide.auth = {
    enable = lib.mkEnableOption "the Authelia gate in front of the Graphide stack";

    portalHost = lib.mkOption {
      type = lib.types.str;
      default = "auth.graphide.net";
      description = ''
        Authelia's login portal on the Graphide apex.

        It needs one of its own: an Authelia session cookie is scoped to a single
        apex domain, so the cookie issued at auth.mcgeedan.com cannot cover
        graphide.net no matter who is logged in.
      '';
    };

    upstream = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1:9091";
      description = "Where Authelia listens. Declared by system/serv/auth.nix.";
    };

    apexDomains = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "graphide.net" "graphide.dev" ];
      description = ''
        Apexes serving the marketing site. Kept identical on purpose -- they
        serve the same container, and the two drifting apart is how one of them
        ends up with an unprotected results page.

        Caveat for graphide.dev: session.cookies below covers graphide.net only,
        so Authelia cannot issue graphide.dev a cookie. Its bypass rules are
        unaffected, but its two admin paths 401 rather than redirecting to a
        portal. That is a deliberate fail-closed and it predates this file.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = config.serv.auth.enable;
        message = ''
          graphide.auth requires serv.auth.enable — the Authelia instance itself
          is declared in system/serv/auth.nix, and this module only points at
          it. Turning the mcgeedan estate off is fine, but keep
          serv.auth.enable = true in the host file until the demo pods have
          moved to the signed-token gate and the admin pages have somewhere else
          to live.
        '';
      }
    ];

    # Graphide's own copy of the snippet. system/serv/auth.nix defines an
    # identical one, but that one is emitted into the SHARED Caddy's config and
    # this tree runs its own process, so it needs its own. Two definitions of
    # six lines is the price of the two Caddys not being able to break each
    # other, and it is the right trade.
    graphide.network.extraConfig = ''
      (require_auth) {
        forward_auth ${cfg.upstream} {
          uri /api/authz/forward-auth
          header_up X-Forwarded-Proto https
          copy_headers Remote-User Remote-Groups Remote-Name Remote-Email
        }
      }
    '';

    graphide.network.virtualHosts."http://${cfg.portalHost}".extraConfig = ''
      reverse_proxy ${cfg.upstream}
    '';

    services.authelia.instances.main.settings = {
      # mkAfter so this lands behind the mcgeedan cookie definition rather than
      # racing it. Authelia picks the cookie config by matching the request
      # domain, so order is not load-bearing here -- it is only tidiness.
      session.cookies = lib.mkAfter [{
        domain = "graphide.net";
        authelia_url = "https://${cfg.portalHost}";
        default_redirection_url = "https://graphide.net";
        expiration = "2h";
        inactivity = "30m";
      }];

      # ONE mkBefore list for the whole Graphide side, which is a simplification
      # worth noting: these rules used to be split across two files at two
      # different merge priorities, and reasoning about the resulting order took
      # a forty-line comment. Authelia takes the FIRST matching rule, so what
      # actually matters is the order within this list:
      #
      #   1. the portal itself, which must be reachable without auth
      #   2. the per-box rules, group-scoped
      #   3. the admin resources on each apex, BEFORE
      #   4. that apex's public bypass
      #
      # Getting 3 and 4 the wrong way round does not error; it just publishes
      # the results pages. mkBefore keeps the whole block ahead of the
      # mcgeedan.com rules in system/serv/auth.nix, which is belt and braces --
      # Authelia matches `domain` exactly unless it is a wildcard, so no
      # mcgeedan rule could match a graphide host anyway.
      access_control.rules = lib.mkBefore (
        [{ domain = cfg.portalHost; policy = "bypass"; }]
        ++ boxRules
        ++ apexRules
      );
    };
  };
}
