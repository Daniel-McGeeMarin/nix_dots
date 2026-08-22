{ config, lib, ... }:
{
  options.serv.dashboard.enable = lib.mkEnableOption "Homarr dashboard";

  config = lib.mkIf config.serv.dashboard.enable {
    age.secrets.homarr-env = {
      file = ../../secrets/homarr-env.age;
      mode = "0400";
    };

    systemd.tmpfiles.rules = [
      "d /srv/data/homarr 0755 root root"
    ];

    virtualisation.oci-containers.containers.homarr = {
      image            = "ghcr.io/homarr-labs/homarr:latest";
      ports            = [ "127.0.0.1:7575:7575" ];
      volumes          = [ "/srv/data/homarr:/appdata" ];
      environmentFiles = [ config.age.secrets.homarr-env.path ];
      labels           = { "io.containers.autoupdate" = "registry"; };
    };

    services.caddy.virtualHosts."http://hq.mcgeedan.com".extraConfig = ''
      import require_auth
      reverse_proxy 127.0.0.1:7575
    '';
  };
}
