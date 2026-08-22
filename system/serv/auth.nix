{ config, lib, ... }:
{
  options.serv.auth.enable = lib.mkEnableOption "Authelia SSO";

  config = lib.mkIf config.serv.auth.enable {
    # Owned by the authelia user, not root: the module's validate-config
    # pre-start opens these paths directly as that user, so 0400 root-owned
    # fails closed at startup rather than at first request.
    age.secrets = let
      forAuthelia = file: {
        inherit file;
        mode = "0400";
        owner = config.services.authelia.instances.main.user;
        group = config.services.authelia.instances.main.group;
      };
    in {
      authelia-jwt     = forAuthelia ../../secrets/authelia-jwt.age;
      authelia-session = forAuthelia ../../secrets/authelia-session.age;
      authelia-storage = forAuthelia ../../secrets/authelia-storage.age;
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
            # Jobs admin/queue endpoints require login; the browse view is public
            { domain = "mcgeedan.com"; resources = [ "^/api/jobs/queue(/.*)?$" "^/api/jobs/refresh(/.*)?$" "^/api/jobs/enrich(/.*)?$" "^/api/jobs/custom-mapper" ]; policy = "one_factor"; }
            # Saved resume storage is personal — require login
            { domain = "mcgeedan.com"; resources = [ "^/api/resume/saved(/.*)?$" ]; policy = "one_factor"; }
            # Survey results — private admin view
            { domain = "mcgeedan.com"; resources = [ "^/survey/results(/.*)?$" "^/api/survey/results(/.*)?$" ]; policy = "one_factor"; }
            # Rest of the main site is public
            { domain = "mcgeedan.com"; policy = "bypass"; }
            # Everything else on subdomains requires one-factor login
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

    systemd.services.authelia-main.serviceConfig.ReadWritePaths = [ "/srv/data/authelia" ];

    services.caddy = {
      # Reusable snippet — add `import require_auth` to any protected virtual host
      extraConfig = ''
        (require_auth) {
          forward_auth 127.0.0.1:9091 {
            uri /api/authz/forward-auth
            header_up X-Forwarded-Proto https
            copy_headers Remote-User Remote-Groups Remote-Name Remote-Email
          }
        }
      '';
      virtualHosts."http://auth.mcgeedan.com".extraConfig = ''
        reverse_proxy 127.0.0.1:9091
      '';
    };
  };
}
