{ config, lib, ... }:
{
  options.serv.auth.enable = lib.mkEnableOption "Authelia SSO";

  config = lib.mkIf config.serv.auth.enable {
    age.secrets = {
      authelia-jwt     = { file = ../../secrets/authelia-jwt.age;     mode = "0444"; };
      authelia-session = { file = ../../secrets/authelia-session.age; mode = "0444"; };
      authelia-storage = { file = ../../secrets/authelia-storage.age; mode = "0444"; };
    };

    services.authelia.instances.main = {
      enable = true;
      secrets = {
        jwtSecretFile            = config.age.secrets.authelia-jwt.path;
        sessionSecretFile        = config.age.secrets.authelia-session.path;
        storageEncryptionKeyFile = config.age.secrets.authelia-storage.path;
      };
      settings = {
        theme     = "dark";
        log.level = "info";
        server.address = "tcp://0.0.0.0:9091";

        authentication_backend.file = {
          path  = "/srv/data/authelia/users.yml";
          watch = true;
        };

        access_control = {
          default_policy = "deny";
          rules = [
            # Authelia's own login portal must be reachable without auth
            { domain = "auth.mcgeedan.com"; policy = "bypass"; }
            # Everything else on the domain requires one-factor login
            { domain = "*.mcgeedan.com"; policy = "one_factor"; }
          ];
        };

        session.cookies = [{
          domain                   = "mcgeedan.com";
          authelia_url             = "https://auth.mcgeedan.com";
          default_redirection_url  = "https://hq.mcgeedan.com";
          expiration               = "12h";
          inactivity               = "30m";
        }];

        storage.local.path = "/srv/data/authelia/db.sqlite3";

        notifier.filesystem.filename = "/srv/data/authelia/notifications.txt";
      };
    };

    services.caddy = {
      # Reusable snippet — add `import require_auth` to any protected virtual host
      extraConfig = ''
        (require_auth) {
          forward_auth localhost:9091 {
            uri /api/authz/forward-auth
            copy_headers Remote-User Remote-Groups Remote-Name Remote-Email
          }
        }
      '';
      virtualHosts."http://auth.mcgeedan.com".extraConfig = ''
        reverse_proxy localhost:9091
      '';
    };
  };
}
