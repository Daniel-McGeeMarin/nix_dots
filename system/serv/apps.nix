{ config, lib, pkgs, ... }:
{
  options.serv.apps.site.enable = lib.mkEnableOption "personal site";

  config = lib.mkIf config.serv.apps.site.enable {
    virtualisation.oci-containers.containers.site = {
      image  = "ghcr.io/daniel-mcgeemarin/mcgeeinfov2:latest";
      ports  = [ "127.0.0.1:3001:80" ];
      labels."io.containers.autoupdate" = "registry";
    };

    services.caddy.virtualHosts = {
      "http://mcgeedan.com".extraConfig = ''
        reverse_proxy 127.0.0.1:3001
      '';
      "http://www.mcgeedan.com".extraConfig = ''
        redir http://mcgeedan.com{uri} permanent
      '';
    };

    # Pull updated container images every 5 minutes
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
