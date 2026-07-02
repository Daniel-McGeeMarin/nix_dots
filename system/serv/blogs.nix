{ config, lib, ... }:
{
  options.serv.blogs.enable = lib.mkEnableOption "Ghost blogs";

  config = lib.mkIf config.serv.blogs.enable {
    age.secrets = {
      ghost-public-env  = { file = ../../secrets/ghost-public-env.age;  mode = "0444"; };
      ghost-private-env = { file = ../../secrets/ghost-private-env.age; mode = "0444"; };
    };

    virtualisation.oci-containers.containers = {
      ghost-public = {
        image = "ghost:5-alpine";
        ports = [ "127.0.0.1:2368:2368" ];
        volumes = [ "/srv/data/ghost-public/content:/var/lib/ghost/content" ];
        environment = {
          url                              = "https://blog.mcgeedan.com";
          NODE_ENV                         = "production";
          database__client                 = "sqlite3";
          database__connection__filename   = "/var/lib/ghost/content/data/ghost.db";
        };
        environmentFiles = [ config.age.secrets.ghost-public-env.path ];
        labels = { "io.containers.autoupdate" = "registry"; };
      };

      ghost-private = {
        image = "ghost:5-alpine";
        ports = [ "127.0.0.1:2369:2368" ];
        volumes = [ "/srv/data/ghost-private/content:/var/lib/ghost/content" ];
        environment = {
          url                              = "https://journal.mcgeedan.com";
          NODE_ENV                         = "production";
          database__client                 = "sqlite3";
          database__connection__filename   = "/var/lib/ghost/content/data/ghost.db";
        };
        environmentFiles = [ config.age.secrets.ghost-private-env.path ];
        labels = { "io.containers.autoupdate" = "registry"; };
      };
    };

    services.caddy.virtualHosts = {
      "http://blog.mcgeedan.com".extraConfig = ''
        @admin path_regexp ^/ghost(/.*)?$
        forward_auth @admin 127.0.0.1:9091 {
          uri /api/authz/forward-auth
          copy_headers Remote-User Remote-Groups Remote-Name Remote-Email
        }
        reverse_proxy 127.0.0.1:2368
      '';

      "http://journal.mcgeedan.com".extraConfig = ''
        @admin path_regexp ^/ghost(/.*)?$
        forward_auth @admin 127.0.0.1:9091 {
          uri /api/authz/forward-auth
          copy_headers Remote-User Remote-Groups Remote-Name Remote-Email
        }
        reverse_proxy 127.0.0.1:2369
      '';
    };

    systemd.tmpfiles.rules = [
      "d /srv/data/ghost-public/content  0755 root root"
      "d /srv/data/ghost-private/content 0755 root root"
    ];
  };
}
