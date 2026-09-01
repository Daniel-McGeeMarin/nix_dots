{ config, lib, ... }:
# ============================================================================
# THE ONE REMAINING DEPENDENCY ON system/serv
# ----------------------------------------------------------------------------
# Everything else in this tree stands alone. This file does not: it points at
# the Authelia instance declared in system/serv/auth.nix, so the host must keep
# `serv.auth.enable = true` even when the rest of the estate is switched off.
#
# That is deliberate and it is confined to this one file, so the cost of cutting
# it later is known rather than discovered. The demo boxes no longer live here
# — they moved to the signed-token gate in ./gate.nix. Authelia is admin-only:
# one person, at /demo and /feedback/results. Guests never get an Authelia
# account; they get a magic link.
# ============================================================================
let
  cfg = config.graphide.auth;

  # The private admin views. The rendered page comes from the static site and
  # the data behind it from website-api, so both need the same gate or the page
  # is protected and the JSON it fetches is not.
  #
  # /api/demo/release and /api/demo/mint are named here for a functional
  # reason rather than a security one: a path not listed falls through to the
  # domain-wide bypass below, and on a bypass Authelia authenticates nobody
  # and returns no Remote-* headers. Caddy's copy_headers blanks the headers
  # it is told to copy when the auth response omits them, so the endpoint was
  # simultaneously secure and dead -- the API's admin check saw an empty group
  # list and 403'd real admins too.
  adminResources = [
    "^/feedback/results(/.*)?$"
    "^/api/feedback/results(/.*)?$"
    "^/api/demo/release(/.*)?$"
    "^/api/demo/mint(/.*)?$"
    "^/api/demo/status(/.*)?$"
    "^/demo(/.*)?$"
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
    enable = lib.mkEnableOption "the Authelia gate in front of Graphide admin pages";

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
      default = [ "graphide.net" ];
      description = ''
        Apex serving the marketing site. There is one: graphide.net.
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
          serv.auth.enable = true in the host file until the admin pages have
          somewhere else to live.
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
        default_redirection_url = "https://graphide.net/demo";
        expiration = "2h";
        inactivity = "30m";
      }];

      # ONE mkBefore list for the Graphide admin side. Authelia takes the FIRST
      # matching rule, so order within this list is:
      #
      #   1. the portal itself, reachable without auth
      #   2. the admin resources on each apex, BEFORE
      #   3. that apex's public bypass
      #
      # Getting 2 and 3 the wrong way round does not error; it just publishes
      # the results pages. The demo boxes are not in this list: they are gated
      # by graphide-gate, not Authelia. An unlisted host falls through to
      # default_policy = deny, which is correct — nobody should be hitting
      # Authelia for demobox1.graphide.net any more.
      access_control.rules = lib.mkBefore (
        [{ domain = cfg.portalHost; policy = "bypass"; }]
        ++ apexRules
      );
    };
  };
}
