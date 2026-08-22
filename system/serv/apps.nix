{ config, lib, pkgs, ... }:
{
  options.serv.apps.site.enable = lib.mkEnableOption "personal site";

  config = lib.mkIf config.serv.apps.site.enable {
    age.secrets.finance-plaid-env = { file = ../../secrets/finance-plaid-env.age; mode = "0400"; };

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
        environmentFiles = [ config.age.secrets.finance-plaid-env.path ];
        environment = {
          FINANCE_DB_PATH = "/data/finance.db";
          PLAID_ENV       = "production";
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

    services.caddy.virtualHosts."http://finances.mcgeedan.com".extraConfig = ''
      import require_auth
      handle /api/* {
        reverse_proxy 127.0.0.1:8001
      }
      handle {
        reverse_proxy 127.0.0.1:3010
      }
    '';

    systemd.timers.podman-auto-update = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "*:0/5";
        Persistent  = true;
      };
    };

    systemd.services.podman-auto-update = {
      serviceConfig.ExecStart = lib.mkForce "${pkgs.podman}/bin/podman auto-update";
    };
  };
}
