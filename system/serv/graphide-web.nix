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

    # graphide.net goes through Caddy rather than having the tunnel point
    # straight at :3003. The demo pods need a *.graphide.net wildcard on :80,
    # and a wildcard plus a more specific tunnel rule is order-dependent in a
    # way that silently swallowed the apex once already. One ingress rule to
    # Caddy for the whole zone keeps the routing in this file instead.
    services.caddy.virtualHosts = {
      "http://graphide.dev".extraConfig = ''
        reverse_proxy 127.0.0.1:3003 {
          header_up X-Forwarded-Proto https
        }
      '';
      "http://www.graphide.dev".extraConfig = ''
        redir https://graphide.dev{uri} permanent
      '';
      "http://graphide.net".extraConfig = ''
        reverse_proxy 127.0.0.1:3003 {
          header_up X-Forwarded-Proto https
        }
      '';
      "http://www.graphide.net".extraConfig = ''
        redir https://graphide.net{uri} permanent
      '';
    };
  };
}
