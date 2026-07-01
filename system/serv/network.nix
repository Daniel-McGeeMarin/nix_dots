{ config, lib, pkgs, ... }:
{
  options.serv.network.enable = lib.mkEnableOption "Caddy reverse proxy and Cloudflare Tunnel";

  config = lib.mkIf config.serv.network.enable {
    age.secrets.cloudflare-tunnel = {
      file = ../../secrets/cloudflare-tunnel.age;
      owner = "cloudflared";
    };

    users.users.cloudflared = {
      isSystemUser = true;
      group = "cloudflared";
    };
    users.groups.cloudflared = {};

    # cloudflared reads TUNNEL_TOKEN from the EnvironmentFile.
    # Secret format: TUNNEL_TOKEN=<paste token from Cloudflare dashboard>
    systemd.services.cloudflared = {
      description = "Cloudflare Tunnel";
      after = [ "network-online.target" "agenix.service" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        EnvironmentFile = config.age.secrets.cloudflare-tunnel.path;
        ExecStart = "${pkgs.cloudflared}/bin/cloudflared tunnel --no-autoupdate run";
        Restart = "on-failure";
        RestartSec = "5s";
        User = "cloudflared";
        Group = "cloudflared";
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = true;
      };
    };

    # Caddy — virtual hosts are declared in each service module alongside
    # the container they front.  Nothing to put here until the first service lands.
    services.caddy.enable = true;
  };
}
