# Graphide demo pods — throwaway browser IDEs handed out by invite.
#
# Each session is one container running the entire product with no external
# dependencies: postgres, redis, graphide-api, grug and a VSCodium reh-web
# server with the Graphide extension. The guest opens a link and is already
# signed in; the container mints its own API token at boot.
#
# == Why each session gets its own container ==
#
# grug is single-workspace and its HTTP surface has no authentication at all —
# the socket path is the entire access boundary. Two guests sharing one pod
# would share the same graph, the same files, the same agent session and the
# same shell. Per-session containers are a correctness requirement, not a
# scaling choice.
#
# == The threat model, stated plainly ==
#
# A guest is GIVEN a shell. VS Code ships a terminal, and grug runs
# model-authored `sh -c` with no sandbox (monolith grug/relay/shell.go). So the
# container boundary is the only boundary, and the isolation below is what
# makes handing out the link acceptable:
#
#   - Dedicated podman network. Containers on the default network can reach
#     each other directly by IP; ocis, onlyoffice and the site containers all
#     live there. A separate bridge is what keeps a demo pod away from them.
#   - The NixOS firewall already drops podman -> host (see ocis.nix, which has
#     to explicitly re-open 443 for exactly this reason), so authelia on
#     0.0.0.0:9091 and ocis on 0.0.0.0:9200 are not reachable from a pod.
#   - Published on 127.0.0.1 only, so Caddy is the sole ingress and Authelia
#     is unavoidable.
#   - cap-drop=ALL, no-new-privileges, and cpu/memory/pid ceilings so a
#     runaway agent cannot take the box down.
#
# The provider API key is the one secret that must live inside a pod, and any
# guest can read it from a terminal. Use a dedicated key with a low spend cap,
# never the production one.
#
# == Setup ==
#
# 1. secrets/graphide-demo-env.age (agenix -e), one KEY=value per line:
#      ANTHROPIC_API_KEY=sk-ant-...      # or OPENROUTER_API_KEY
# 2. Point demo.graphide.net and auth.graphide.net at the graphide Cloudflare
#    tunnel.
# 3. Add guests to /srv/data/authelia/users.yml.
# 4. serv.graphide-demo.enable = true; and list the sessions.

{ config, lib, pkgs, ... }:

let
  cfg = config.serv.graphide-demo;

  # Ports are assigned from a base rather than configured per session: they are
  # loopback-only plumbing between Caddy and podman, and nothing outside this
  # file needs to know them.
  portFor = i: cfg.basePort + i;

  sessionList = lib.imap0 (i: name: { inherit name; index = i; port = portFor i; }) cfg.sessions;

  containerFor = s: lib.nameValuePair "graphide-demo-${s.name}" {
    image = cfg.image;
    # Loopback only. Caddy reaches it; nothing else on the network can.
    ports = [ "127.0.0.1:${toString s.port}:8000" ];
    environmentFiles = [ config.age.secrets.graphide-demo-env.path ];
    environment = {
      DEMO_EMAIL = "${s.name}@demo.graphide.net";
      # Distinct per session so two pods never mint the same user id.
      DEMO_SUB = "00000000-0000-4000-8000-${lib.fixedWidthString 12 "0" (toString (s.index + 1))}";
    };
    extraOptions = [
      "--network=${cfg.networkName}"
      "--cap-drop=ALL"
      "--security-opt=no-new-privileges"
      "--memory=${cfg.memoryLimit}"
      "--cpus=${toString cfg.cpuLimit}"
      "--pids-limit=512"
    ];
    labels."io.containers.autoupdate" = "registry";
  };

  # Authelia gates the whole vhost. The pod itself runs without a connection
  # token because it is unreachable except through this proxy.
  vhostFor = s: lib.nameValuePair "http://${s.name}.${cfg.domain}" {
    extraConfig = ''
      import require_auth
      reverse_proxy 127.0.0.1:${toString s.port} {
        header_up X-Forwarded-Proto https
      }
    '';
  };
in
{
  options.serv.graphide-demo = {
    enable = lib.mkEnableOption "Graphide demo pods";

    sessions = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [ "alice" "bob" ];
      description = ''
        One container per name, reachable at <name>.<domain>. Names are the
        subdomain, so keep them DNS-safe.
      '';
    };

    domain = lib.mkOption {
      type = lib.types.str;
      default = "demo.graphide.net";
      description = "Parent domain; each session is a subdomain of it.";
    };

    image = lib.mkOption {
      type = lib.types.str;
      default = "ghcr.io/graphidehq/graphide-demo:latest";
      description = ''
        Fully qualified on purpose: podman refuses short names for any
        container labelled io.containers.autoupdate = "registry".
      '';
    };

    basePort = lib.mkOption {
      type = lib.types.port;
      default = 8100;
      description = "First loopback port; sessions take consecutive ports.";
    };

    networkName = lib.mkOption {
      type = lib.types.str;
      default = "graphide-demo";
      description = ''
        A podman network of its own. This is load-bearing: the default network
        would let a pod reach ocis, onlyoffice and the site containers directly.
      '';
    };

    memoryLimit = lib.mkOption {
      type = lib.types.str;
      default = "3g";
    };

    cpuLimit = lib.mkOption {
      type = lib.types.number;
      default = 2;
    };

    recycle = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Restart every pod on a timer. Restarting is what expires a guest
          link's usefulness: the container comes back with a fresh database,
          a fresh workspace and a newly minted token, so anything the previous
          guest did is gone.
        '';
      };
      interval = lib.mkOption {
        type = lib.types.str;
        default = "hourly";
        description = "systemd OnCalendar expression.";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = config.serv.auth.enable;
        message = ''
          serv.graphide-demo requires serv.auth.enable — the pods hand out a
          shell and Authelia is the only thing in front of them.
        '';
      }
      {
        assertion = cfg.sessions == lib.unique cfg.sessions;
        message = "serv.graphide-demo.sessions has duplicates; each name is a subdomain.";
      }
    ];

    age.secrets.graphide-demo-env = {
      file = ../../secrets/graphide-demo-env.age;
      mode = "0400";
    };

    # oci-containers has no notion of networks, so create it once at boot.
    # Everything else that needs a systemd unit is merged into this one
    # attribute: Nix rejects `systemd.services.foo = {}` alongside a later
    # `systemd.services = {...}` in the same attrset.
    systemd.services = lib.mkMerge [
      {
        graphide-demo-network = {
          description = "Create the isolated podman network for Graphide demo pods";
          after = [ "network-online.target" ];
          wants = [ "network-online.target" ];
          wantedBy = [ "multi-user.target" ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
          };
          script = ''
            if ! ${pkgs.podman}/bin/podman network exists ${cfg.networkName}; then
              ${pkgs.podman}/bin/podman network create ${cfg.networkName}
            fi
          '';
        };
      }

      # Every pod waits for its network, and for the GHCR login the graphide
      # module already sets up (the demo image is in the same private registry).
      (builtins.listToAttrs (map (s:
        lib.nameValuePair "podman-graphide-demo-${s.name}" {
          after = [ "graphide-demo-network.service" "graphide-ghcr-login.service" ];
          requires = [ "graphide-demo-network.service" ];
        }) sessionList))

      # What the recycle timers actually trigger. Restarting is the expiry
      # mechanism: the container comes back with a fresh database, a fresh
      # workspace and a newly minted token.
      (lib.mkIf cfg.recycle.enable (builtins.listToAttrs (map (s:
        lib.nameValuePair "graphide-demo-recycle-${s.name}" {
          description = "Recycle the ${s.name} Graphide demo pod";
          serviceConfig = {
            Type = "oneshot";
            ExecStart = "${pkgs.systemd}/bin/systemctl restart podman-graphide-demo-${s.name}.service";
          };
        }) sessionList)))
    ];

    virtualisation.oci-containers.containers =
      builtins.listToAttrs (map containerFor sessionList);

    services.caddy.virtualHosts = lib.mkMerge [
      (builtins.listToAttrs (map vhostFor sessionList))
      {
        "http://auth.graphide.net".extraConfig = ''
          reverse_proxy 127.0.0.1:9091
        '';
      }
    ];

    # Authelia's existing cookie is scoped to mcgeedan.com and does not cover a
    # different apex, so graphide.net needs its own session config and portal.
    services.authelia.instances.main.settings = {
      session.cookies = lib.mkAfter [{
        domain = "graphide.net";
        authelia_url = "https://auth.graphide.net";
        default_redirection_url = "https://graphide.net";
        expiration = "2h";
        inactivity = "30m";
      }];

      access_control.rules = lib.mkBefore ([
        { domain = "auth.graphide.net"; policy = "bypass"; }
      ] ++ map (s: {
        domain = "${s.name}.${cfg.domain}";
        policy = "one_factor";
      }) sessionList);
    };

    systemd.timers = lib.mkIf cfg.recycle.enable (builtins.listToAttrs (map (s:
      lib.nameValuePair "graphide-demo-recycle-${s.name}" {
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnCalendar = cfg.recycle.interval;
          Persistent = false;
          RandomizedDelaySec = "5m";
        };
      }) sessionList));
  };
}
