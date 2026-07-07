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
        ports  = [ "127.0.0.1:8000:8000" ];
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
