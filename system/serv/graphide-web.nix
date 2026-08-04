{ config, lib, ... }:
{
  options.serv.graphide-web.enable = lib.mkEnableOption "Graphide marketing site";

  config = lib.mkIf config.serv.graphide-web.enable {
    virtualisation.oci-containers.containers = {
      graphide-web = {
        image  = "ghcr.io/graphidehq/website:latest";
        ports  = [ "127.0.0.1:3003:80" ];
        labels."io.containers.autoupdate" = "registry";
      };
    };

    services.caddy.virtualHosts = {
      "http://graphide.dev".extraConfig = ''
        reverse_proxy 127.0.0.1:3003 {
          header_up X-Forwarded-Proto https
        }
      '';
      "http://www.graphide.dev".extraConfig = ''
        redir https://graphide.dev{uri} permanent
      '';
    };
  };
}
