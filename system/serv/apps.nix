{ config, lib, pkgs, ... }:
{
  options.serv.apps.site.enable = lib.mkEnableOption "personal site";

  config = lib.mkIf config.serv.apps.site.enable {
    virtualisation.oci-containers.containers = {
      site-web = {
        image  = "ghcr.io/daniel-mcgeemarin/mcgeeinfov2-web:latest";
        ports  = [ "127.0.0.1:3001:80" ];
        labels."io.containers.autoupdate" = "registry";
      };
      site-api = {
        image  = "ghcr.io/daniel-mcgeemarin/mcgeeinfov2-api:latest";
        # Bind on all interfaces so the onlyoffice container can reach the temp-DOCX
        # endpoint via the Podman host gateway (10.88.0.1).  Caddy still gates /api/*
        # from the public internet; port 8000 is opened only on the podman bridge below.
        ports  = [ "0.0.0.0:8000:8000" ];
        volumes = [ "/srv/data/site-api:/data" ];
        environment = {
          JOBS_DB_PATH    = "/data/jobs.db";
          MODELFIT_DB     = "/data/modelfit_sessions.db";
          # URL that the onlyoffice container uses to fetch temp DOCX files from us.
          # 10.88.0.1 is the Podman bridge gateway — reachable from every container.
          SITE_API_URL    = "http://10.88.0.1:8000";
          ONLYOFFICE_URL  = "http://onlyoffice";
        };
        labels."io.containers.autoupdate" = "registry";
      };
    };

    services.caddy.virtualHosts."http://www.mcgeedan.com".extraConfig = ''
      redir https://mcgeedan.com{uri} permanent
    '';

    services.caddy.virtualHosts."http://mcgeedan.com".extraConfig = ''
      handle /api/jobs* {
        import require_auth
        reverse_proxy 127.0.0.1:8000
      }
      handle /api/* {
        reverse_proxy 127.0.0.1:8000
      }
      handle /apps/jobs* {
        import require_auth
        reverse_proxy 127.0.0.1:3001
      }
      handle {
        reverse_proxy 127.0.0.1:3001
      }
    '';

    # Allow the onlyoffice container to fetch temp DOCX files from site-api via the
    # Podman bridge gateway.  Restrict to the podman bridge interface so port 8000
    # is not reachable from the WAN (Caddy is the public entry point for /api/*).
    networking.firewall.interfaces."podman0".allowedTCPPorts = [ 8000 ];

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
