{ config, lib, ... }:
{
  options.serv.dashboard.enable = lib.mkEnableOption "Homarr dashboard";

  config = lib.mkIf config.serv.dashboard.enable {
    systemd.tmpfiles.rules = [
      "d /srv/data/homarr 0755 root root"
    ];

    virtualisation.oci-containers.containers.homarr = {
      image   = "ghcr.io/homarr-labs/homarr:latest";
      ports   = [ "127.0.0.1:7575:7575" ];
      volumes = [ "/srv/data/homarr:/appdata" ];
      labels  = { "io.containers.autoupdate" = "registry"; };
    };

    services.caddy.virtualHosts."http://dash.mcgeedan.com".extraConfig = ''
      import require_auth
      reverse_proxy localhost:7575
    '';
  };
}
