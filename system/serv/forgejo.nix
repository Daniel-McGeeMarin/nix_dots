{ config, lib, ... }:
{
  options.serv.forgejo.enable = lib.mkEnableOption "Forgejo git forge";

  config = lib.mkIf config.serv.forgejo.enable {
    systemd.tmpfiles.rules = [
      "d /srv/data/forgejo 0750 1000 1000"
    ];

    # SSH published on 2222, not 22 — the host's own sshd (serv/default.nix) owns 22.
    # Only HTTP is routed through Caddy/Cloudflare below; exposing git+ssh publicly
    # would need a separate TCP ingress rule added in the Cloudflare Tunnel dashboard
    # (ingress rules for this tunnel aren't in this repo — see network.nix).
    virtualisation.oci-containers.containers.forgejo = {
      image   = "codeberg.org/forgejo/forgejo:10";
      ports   = [ "127.0.0.1:3002:3000" "127.0.0.1:2222:22" ];
      volumes = [ "/srv/data/forgejo:/data" ];
      environment = {
        FORGEJO__server__DOMAIN               = "git.mcgeedan.com";
        FORGEJO__server__ROOT_URL             = "https://git.mcgeedan.com/";
        FORGEJO__server__SSH_DOMAIN           = "git.mcgeedan.com";
        FORGEJO__server__SSH_PORT             = "2222";
        FORGEJO__service__DISABLE_REGISTRATION = "true";
      };
      labels."io.containers.autoupdate" = "registry";
    };

    services.caddy.virtualHosts."http://git.mcgeedan.com".extraConfig = ''
      reverse_proxy 127.0.0.1:3002 {
        header_up X-Forwarded-Proto https
      }
    '';
  };
}
