# Graphide API server — three Podman containers (postgres, redis, API) on host
# networking, managed as systemd services via virtualisation.oci-containers.
#
# == New system setup checklist ==
#
# 1. Secrets — two age-encrypted files in secrets/:
#
#    secrets/graphide/api-env.age  (edit with: agenix -e secrets/graphide/api-env.age)
#      POSTGRES_USER=graphide
#      POSTGRES_DB=graphide
#      POSTGRES_PASSWORD=<strong random>
#      DATABASE_URL=postgres://graphide:<same password>@127.0.0.1:5432/graphide
#      REDIS_URL=redis://127.0.0.1:6379
#      SUPABASE_URL=https://<project>.supabase.co   # base URL only, no path
#      ANTHROPIC_API_KEY=sk-ant-...                 # required for AI jobs; safe to
#                                                    # omit until you're ready — the
#                                                    # server starts without it but
#                                                    # job requests will fail
#      PORT=8080
#
#    secrets/graphide/ghcr-token.age  (edit with: agenix -e secrets/graphide/ghcr-token.age)
#      <GitHub PAT with read:packages scope — no newline>
#
#    Both must be encrypted to the target host's SSH key (see secrets.nix).
#    To create a new PAT: GitHub → Settings → Developer settings →
#    Personal access tokens → Tokens (classic) → read:packages scope.
#
# 2. Supabase — create a project at supabase.com; the Project URL
#    (Settings → API) is all you need for SUPABASE_URL. No tables or
#    auth providers need to be configured to start the server.
#
# 3. GHCR image — ghcr.io/graphidehq/monolith-api:latest is built and
#    pushed automatically by the deploy.yml workflow in the monolith repo
#    on every push to master. The image must exist before first boot.
#
# 4. Enable — set graphide.api.enable = true in the host's configuration.nix.
#
# == Key design decisions and gotchas ==
#
# - Host networking: all three containers share the host network stack so they
#   reach each other on 127.0.0.1 without a Podman pod or internal DNS.
#   Postgres and Redis are bound to 127.0.0.1 only — not exposed externally.
#
# - Postgres data dir ownership: postgres:17-alpine runs postgres as UID 70.
#   The data dir must be owned by UID 70 or postgres refuses to start.
#   systemd tmpfiles creates it with the right owner on fresh systems;
#   ExecStartPre chowns it on every boot to fix any ownership drift.
#   (Root-owned dir was the original failure mode — caused a crash loop.)
#
# - Startup sequencing: NixOS oci-containers' `dependsOn` only waits for
#   the container *service* to start, not for postgres to be ready to accept
#   connections. First boot takes several seconds for initdb to run.
#   graphide-pg-ready polls TCP 5432 for up to 60s before the API starts.
#
# == Verifying the service ==
#
#   curl http://localhost:8080/health   # → {"status":"ok"}  (no DB needed)
#   curl http://localhost:8080/ready    # → {"status":"ok"}  (DB + Redis up)
#
#   journalctl -u podman-graphide-api      -f   # API logs
#   journalctl -u podman-graphide-postgres -f   # postgres logs
#   journalctl -u graphide-pg-ready        -f   # startup sequencing
#   podman ps                                   # running containers

{ config, lib, pkgs, ... }:
{
  options.graphide.api.enable = lib.mkEnableOption "Graphide API server";

  config = lib.mkIf config.graphide.api.enable {
    age.secrets = {
      graphide-api-env = {
        file = ../../secrets/graphide/api-env.age;
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

    # graphide-ghcr-login lives in ./registry.nix. It used to be declared here,
    # which gave the marketing site and the demo pods a hard dependency on the
    # API server module for a reason that had nothing to do with the API server.

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

    # api.graphide.net is the name to use. It costs nothing to add -- the
    # tunnel already routes *.graphide.net to this box, so no DNS record and no
    # ingress rule is needed -- and it puts the API on the Graphide apex where
    # the rest of the stack lives.
    #
    # graphideapi.mcgeedan.com is kept because clients still use it, but be
    # clear about what it now needs: it is a mcgeedan.com hostname, so it
    # arrives through the mcgeedan TUNNEL, which is declared in
    # system/serv/network.nix and stops with `serv.enable = false`. Even with
    # that tunnel up, its ingress rule points at :80 -- the shared Caddy, which
    # no longer has this vhost. To keep the old name alive, add an ingress rule
    # for it pointing at 127.0.0.1:${toString config.graphide.network.port}.
    # Otherwise migrate clients to api.graphide.net and delete this entry.
    graphide.network.virtualHosts = let
      apiProxy = ''
        reverse_proxy 127.0.0.1:8080 {
          header_up X-Forwarded-Proto https
        }
      '';
    in {
      "http://api.graphide.net".extraConfig = apiProxy;
      "http://graphideapi.mcgeedan.com".extraConfig = apiProxy;
    };
  };
}
