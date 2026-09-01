{ config, lib, pkgs, ... }:
let
  # Both of these secrets were wired up before they were ever created, which left
  # XiaServer undeployable. The wiring is self-enabling instead: absent secret,
  # absent feature, and the host still evaluates. Footgun when creating them — a
  # flake only copies git-tracked files into the store, so a fresh .age file is
  # invisible to pathExists until it has been `git add`ed.
  ofxEnvFile      = ../../secrets/core/finance-ofx-env.age;
  importTokenFile = ../../secrets/core/finance-import-token.age;
  haveOfxEnv      = builtins.pathExists ofxEnvFile;
  haveImportToken = builtins.pathExists importTokenFile;
in
{
  options.serv.apps.site.enable = lib.mkEnableOption "personal site";

  config = lib.mkIf config.serv.apps.site.enable {
    age.secrets =
      # OFX Direct Connect credentials — talks straight to the bank, no aggregator.
      #   US_BANK_OFX_USER=...
      #   US_BANK_OFX_PASSWORD=...
      #   US_BANK_OFX_ACCOUNTS=CHECKING:<acct>:<routing>,CREDITCARD:<acct>
      lib.optionalAttrs haveOfxEnv {
        finance-ofx-env = { file = ofxEnvFile; mode = "0400"; };
      }
      # Read by Caddy, never by the API, to gate the extension's import route:
      #   FINANCE_IMPORT_TOKEN=<long random string>
      # Must be non-empty; see the @ext_import note on the finances vhost below.
      // lib.optionalAttrs haveImportToken {
        finance-import-token = { file = importTokenFile; mode = "0400"; owner = "caddy"; };
      };

    systemd.services.caddy.serviceConfig.EnvironmentFile =
      lib.optionals haveImportToken [ config.age.secrets.finance-import-token.path ];

    virtualisation.oci-containers.containers = {
      site-web = {
        image  = "ghcr.io/daniel-mcgeemarin/mcgeeinfov2-web:latest";
        ports  = [ "127.0.0.1:3001:80" ];
        labels."io.containers.autoupdate" = "registry";
      };
      site-api = {
        image  = "ghcr.io/daniel-mcgeemarin/mcgeeinfov2-api:latest";
        ports  = [ "127.0.0.1:8000:8000" ];
        volumes = [ "/srv/data/site-api:/data" ];
        environment = {
          JOBS_DB_PATH    = "/data/jobs.db";
          MODELFIT_DB     = "/data/modelfit_sessions.db";
          RESUME_DB_PATH  = "/data/resume.db";
          SURVEY_DB_PATH  = "/data/survey.db";
        };
        labels."io.containers.autoupdate" = "registry";
      };
      finance-web = {
        image  = "ghcr.io/daniel-mcgeemarin/mcgeeinfov2-finance-web:latest";
        ports  = [ "127.0.0.1:3010:80" ];
        labels."io.containers.autoupdate" = "registry";
      };
      finance-api = {
        image  = "ghcr.io/daniel-mcgeemarin/mcgeeinfov2-finance-api:latest";
        ports  = [ "127.0.0.1:8001:8000" ];
        volumes = [ "/srv/data/finance-api:/data" ];
        environmentFiles =
          lib.optionals haveOfxEnv [ config.age.secrets.finance-ofx-env.path ];
        environment = {
          FINANCE_DB_PATH = "/data/finance.db";
        };
        labels."io.containers.autoupdate" = "registry";
      };
    };

    services.caddy.virtualHosts."http://www.mcgeedan.com".extraConfig = ''
      redir https://mcgeedan.com{uri} permanent
    '';

    services.caddy.virtualHosts."http://mcgeedan.com".extraConfig = ''
      handle /api/jobs/queue* {
        import require_auth
        reverse_proxy 127.0.0.1:8000
      }
      handle /api/jobs/refresh* {
        import require_auth
        reverse_proxy 127.0.0.1:8000
      }
      handle /api/jobs/enrich* {
        import require_auth
        reverse_proxy 127.0.0.1:8000
      }
      handle /api/jobs/custom-mapper* {
        import require_auth
        reverse_proxy 127.0.0.1:8000
      }
      handle /api/resume/saved* {
        import require_auth
        reverse_proxy 127.0.0.1:8000
      }
      handle /survey/results* {
        import require_auth
        reverse_proxy 127.0.0.1:3001
      }
      handle /api/survey/results* {
        import require_auth
        reverse_proxy 127.0.0.1:8000
      }
      handle /api/auth/me {
        rewrite * /api/user/info
        reverse_proxy 127.0.0.1:9091
      }
      handle /api/* {
        reverse_proxy 127.0.0.1:8000
      }
      handle {
        reverse_proxy 127.0.0.1:3001
      }
    '';

    # The browser extension posts statement exports here. It's token-gated rather
    # than session-gated because the Authelia cookie goes idle after 30 minutes,
    # which would silently fail the POST. handle blocks are mutually exclusive and
    # evaluated in order, so require_auth moves inside the two fallthrough blocks.
    #
    # @ext_import is the only route on this host that skips require_auth, and the
    # API does no token check of its own — Caddy is the entire gate. An unset
    # FINANCE_IMPORT_TOKEN expands to the empty string and the matcher stops
    # meaning anything, which would publish /api/finance/import to the internet
    # unauthenticated. It is therefore emitted from the same haveImportToken that
    # declares the secret, so the two cannot exist apart. Never lift this block
    # out of the conditional, and never point it at a variable the EnvironmentFile
    # might leave empty. Without the token the extension still works, just on the
    # Authelia cookie, so the failure mode of leaving it off is a nuisance rather
    # than an outage.
    services.caddy.virtualHosts."http://finances.mcgeedan.com".extraConfig =
      lib.optionalString haveImportToken ''
        @ext_import {
          path /api/finance/import
          header X-Finance-Token {env.FINANCE_IMPORT_TOKEN}
        }
        handle @ext_import {
          reverse_proxy 127.0.0.1:8001
        }

      ''
      + ''
        handle /api/* {
          import require_auth
          reverse_proxy 127.0.0.1:8001
        }

        handle {
          import require_auth
          reverse_proxy 127.0.0.1:3010
        }
      '';

    # The podman-auto-update timer used to live here. It is a host-level
    # concern, not part of the personal site, and every other service on the box
    # depended on it -- so it moved to system/podman.nix, where turning this
    # module off cannot stop the rest of the machine from updating.
  };
}
