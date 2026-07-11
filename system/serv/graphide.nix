{ config, lib, pkgs, ... }:
{
  options.serv.graphide.enable = lib.mkEnableOption "Graphide API server";

  config = lib.mkIf config.serv.graphide.enable {
    age.secrets = {
      graphide-api-env = {
        file = ../../secrets/graphide-api-env.age;
        mode = "0400";
      };
      # Classic PAT with read:packages scope, no expiration.
      ghcr-token = {
        file = ../../secrets/ghcr-token.age;
        mode = "0400";
      };
    };

    systemd.tmpfiles.rules = [
      # UID 70 = postgres user in postgres:17-alpine; must own the data dir.
      "d /srv/data/graphide-pg    0700 70   70"
      "d /srv/data/graphide-redis 0700 root root"
    ];

    # Ensure ownership is correct even when the directory already exists
    # (tmpfiles `d` only sets ownership on creation, not on existing dirs).
    systemd.services."podman-graphide-postgres" = {
      serviceConfig.ExecStartPre = [
        "${pkgs.coreutils}/bin/chown -R 70:70 /srv/data/graphide-pg"
      ];
    };

    # Log into GHCR once at boot so both the container start and the
    # podman-auto-update timer can pull the private image.
    systemd.services.graphide-ghcr-login = {
      description = "Authenticate Podman with GHCR";
      after       = [ "agenix.service" "network-online.target" ];
      wants       = [ "network-online.target" ];
      wantedBy    = [ "multi-user.target" ];
      script = ''
        ${pkgs.podman}/bin/podman login ghcr.io \
          --username Daniel-McGeeMarin \
          --password-stdin < ${config.age.secrets.ghcr-token.path}
      '';
      serviceConfig = {
        Type            = "oneshot";
        RemainAfterExit = true;
      };
    };

    # All three containers use host networking so they reach each other
    # via 127.0.0.1 without a separate Podman network or pod.
    virtualisation.oci-containers.containers = {
      graphide-postgres = {
        image        = "docker.io/library/postgres:17-alpine";
        extraOptions = [ "--network=host" ];
        volumes      = [ "/srv/data/graphide-pg:/var/lib/postgresql/data" ];
        # graphide-api-env supplies POSTGRES_USER, POSTGRES_DB, POSTGRES_PASSWORD.
        environmentFiles = [ config.age.secrets.graphide-api-env.path ];
        # Restrict to loopback only — not exposed beyond the host.
        cmd = [ "postgres" "-c" "listen_addresses=127.0.0.1" ];
        labels."io.containers.autoupdate" = "registry";
      };

      graphide-redis = {
        image        = "docker.io/library/redis:7-alpine";
        extraOptions = [ "--network=host" ];
        volumes      = [ "/srv/data/graphide-redis:/data" ];
        cmd = [ "redis-server" "--appendonly" "yes" "--bind" "127.0.0.1" ];
        labels."io.containers.autoupdate" = "registry";
      };

      graphide-api = {
        image        = "ghcr.io/graphidehq/monolith-api:latest";
        extraOptions = [ "--network=host" ];
        environmentFiles = [ config.age.secrets.graphide-api-env.path ];
        dependsOn    = [ "graphide-postgres" "graphide-redis" ];
        labels."io.containers.autoupdate" = "registry";
      };
    };

    # Wait for PostgreSQL to accept connections before starting the API.
    # dependsOn only waits for the container *service* to start, not for
    # postgres to finish initializing its data directory (which takes several
    # seconds on first boot). This script polls TCP 5432 until it's open.
    systemd.services.graphide-pg-ready = {
      description = "Wait for graphide-postgres to accept connections";
      after       = [ "podman-graphide-postgres.service" ];
      requires    = [ "podman-graphide-postgres.service" ];
      wantedBy    = [ "podman-graphide-api.service" ];
      before      = [ "podman-graphide-api.service" ];
      script = ''
        echo "Waiting for postgres on 127.0.0.1:5432..."
        for i in $(seq 1 60); do
          if ${pkgs.netcat-openbsd}/bin/nc -z 127.0.0.1 5432 2>/dev/null; then
            echo "Postgres ready after $i attempts."
            exit 0
          fi
          sleep 1
        done
        echo "Postgres did not become ready within 60 seconds." >&2
        exit 1
      '';
      serviceConfig = {
        Type            = "oneshot";
        RemainAfterExit = true;
      };
    };

    # Ensure GHCR credentials exist before pulling the private image,
    # and postgres is ready before the API tries to connect.
    systemd.services."podman-graphide-api" = {
      after    = [ "graphide-ghcr-login.service" "graphide-pg-ready.service" ];
      requires = [ "graphide-ghcr-login.service" "graphide-pg-ready.service" ];
    };

    services.caddy.virtualHosts."http://graphideapi.mcgeedan.com".extraConfig = ''
      reverse_proxy 127.0.0.1:8080 {
        header_up X-Forwarded-Proto https
      }
    '';
  };
}
