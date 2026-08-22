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
# 2. One Cloudflare Tunnel route: *.graphide.net -> this host. That single
#    wildcard covers every session plus auth.graphide.net.
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
      DEMO_EMAIL = "${s.name}@${cfg.domain}";
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
    # Only when the image actually comes from a registry. podman auto-update
    # logs a failure every run for a locally built tag it cannot pull.
    labels = lib.optionalAttrs cfg.autoUpdate {
      "io.containers.autoupdate" = "registry";
    };
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
      default = "graphide.net";
      description = ''
        Parent domain; each session is a subdomain of it, so a session named
        "alice" is served at alice.graphide.net.

        The apex rather than demo.graphide.net on purpose: a DNS wildcard
        matches exactly one label, so *.graphide.net covers both the sessions
        and auth.graphide.net, whereas nesting under demo. would need a second
        wildcard for *.demo.graphide.net. One tunnel route instead of two.
      '';
    };

    image = lib.mkOption {
      type = lib.types.str;
      default = "ghcr.io/graphidehq/graphide-demo:latest";
      description = ''
        Fully qualified on purpose: podman refuses short names for any
        container labelled io.containers.autoupdate = "registry".
      '';
    };

    autoUpdate = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Label the containers for podman-auto-update, which the timer in
        apps.nix already runs. Set false when `image` is a tag built on this
        host rather than pulled, so auto-update does not try to pull it.
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

    autoBuild = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Poll the source repos and rebuild the image on this host when they
          change, instead of pulling a prebuilt one from a registry.

          The other services here take images from GHCR because CI builds and
          pushes them. This is the same idea without the round trip: it wants
          no GitHub Actions minutes and no registry, which also means it keeps
          working when Actions is unavailable. The cost is that the build runs
          on this box and nothing gates it — CI's smoke test does not exist
          here, so a broken commit becomes a broken pod. The build is staged
          to a temporary tag and only promoted on success, so a failed build
          leaves the running pods alone.

          Implies a local image, so set image/autoUpdate accordingly.
        '';
      };

      interval = lib.mkOption {
        type = lib.types.str;
        default = "*:0/5";
        description = "systemd OnCalendar expression. Default is every 5 minutes.";
      };

      monolithUrl = lib.mkOption {
        type = lib.types.str;
        default = "https://github.com/GraphideHQ/monolith.git";
      };

      gredUrl = lib.mkOption {
        type = lib.types.str;
        default = "https://github.com/GraphideHQ/gred.git";
      };

      branch = lib.mkOption {
        type = lib.types.attrsOf lib.types.str;
        default = { monolith = "master"; gred = "main"; };
        description = "The two repos do not share a default branch name.";
      };

      tokenFile = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        description = ''
          File holding a GitHub token (fine-grained PAT, read-only, scoped to
          both repos; or a classic PAT with repo scope) able to clone both.
          Defaults to the agenix-managed
          secrets/graphide-demo-token.age, which this module declares for you
          when autoBuild is on; set it to another path to supply your own.

          A PAT rather than a deploy key: GitHub org policy can (and here
          does) disable deploy keys org-wide as "use GitHub Apps instead", a
          restriction that does not apply to personal access tokens. A
          fine-grained PAT scoped read-only to exactly these two repositories
          gets the same blast radius a deploy key would have given.
        '';
      };

      srcDir = lib.mkOption {
        type = lib.types.path;
        default = "/srv/data/graphide-demo/src";
      };
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

    age.secrets = {
      graphide-demo-env = {
        file = ../../secrets/graphide-demo-env.age;
        mode = "0400";
      };
    } // lib.optionalAttrs (cfg.autoBuild.enable && cfg.autoBuild.tokenFile == null) {
      # Only declared when autoBuild needs it — agenix fails the whole
      # activation for a secrets file that does not exist, so a host not using
      # autoBuild must not be made to carry one.
      graphide-demo-token = {
        file = ../../secrets/graphide-demo-token.age;
        mode = "0400";
      };
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

      # Poll both repos and rebuild when either moves.
      #
      # Staged deliberately: the build goes to a scratch tag and is only
      # promoted to the real one after it succeeds, so a broken commit upstream
      # leaves the running pods untouched rather than replacing them with an
      # image that does not boot. There is no smoke test here — that lives in
      # CI — so "it built" is the only gate, which is exactly why the promotion
      # is separate from the build.
      (lib.mkIf cfg.autoBuild.enable {
        graphide-demo-autobuild = {
          description = "Rebuild the Graphide demo pod when its sources change";
          after = [ "network-online.target" "graphide-demo-network.service" ];
          wants = [ "network-online.target" ];
          # bash because build-local.sh is a bash script and a systemd unit's
          # PATH contains only what is listed here; gnutar/gzip because podman
          # shells out to them while assembling the build context.
          path = [
            pkgs.bash
            pkgs.git
            pkgs.podman
            pkgs.openssh
            pkgs.coreutils
            pkgs.gnutar
            pkgs.gzip
            pkgs.gnugrep
            pkgs.gnused
            pkgs.findutils
          ];
          serviceConfig = {
            Type = "oneshot";
            # The build is long and must not be killed halfway by a timer tick.
            TimeoutStartSec = "60min";
          };
          script = let
            src = cfg.autoBuild.srcDir;
            monoBranch = cfg.autoBuild.branch.monolith or "master";
            gredBranch = cfg.autoBuild.branch.gred or "main";
          in ''
            set -euo pipefail
            ${let
                tok = if cfg.autoBuild.tokenFile != null
                      then toString cfg.autoBuild.tokenFile
                      else config.age.secrets.graphide-demo-token.path;
              in ''
              # A bare token is not a valid Basic-auth value; git wants
              # base64("x-access-token:<token>"). GIT_CONFIG_VALUE_0 is an
              # environment variable, not a CLI argument, so this does not
              # appear in `ps` — /proc/<pid>/environ is root-only regardless.
              #
              # `http.extraheader=@<file>` looks like file indirection but is
              # not: git sends the literal string "@/path/to/file" as the
              # header value. Verified the hard way — GitHub silently ignored
              # the malformed header and served a public repo anonymously,
              # which would have meant a private clone 401ing while looking
              # identical to "not yet built" rather than to a credential
              # failure. The header value itself has to be the exported var.
              export GIT_CONFIG_COUNT=1
              export GIT_CONFIG_KEY_0=http.extraheader
              export GIT_CONFIG_VALUE_0="Authorization: Basic $(printf 'x-access-token:%s' "$(cat ${tok})" | base64 -w0)"
              # No TTY on a systemd service — without this, an expired or bad
              # token hangs at an interactive credential prompt that can never
              # be answered, rather than failing into the journal.
              export GIT_TERMINAL_PROMPT=0
            ''}
            mkdir -p ${src}

            sync_repo() {
              local url="$1" dir="$2" branch="$3"
              if [ ! -d "$dir/.git" ]; then
                echo "cloning $url"
                git clone --branch "$branch" "$url" "$dir"
              else
                git -C "$dir" fetch --quiet origin "$branch"
                git -C "$dir" checkout --quiet -B "$branch" "origin/$branch"
              fi
              git -C "$dir" rev-parse HEAD
            }

            mono_sha=$(sync_repo "${cfg.autoBuild.monolithUrl}" "${src}/monolith" "${monoBranch}")
            gred_sha=$(sync_repo "${cfg.autoBuild.gredUrl}"     "${src}/gred"     "${gredBranch}")
            current="$mono_sha-$gred_sha"

            stamp="${src}/.last-built"
            if [ -f "$stamp" ] && [ "$(cat "$stamp")" = "$current" ]; then
              echo "no change since last build ($current)"
              exit 0
            fi

            echo "building $current"
            # Staging tag: promoted only on success, so the running pods keep
            # whatever last worked if this build fails.
            staging="localhost/graphide-demo:building"
            TAG="$staging" GRED_DIR="${src}/gred" \
              bash "${src}/monolith/deploy/demo-pod/build-local.sh"

            podman tag "$staging" "${cfg.image}"
            echo "$current" > "$stamp"

            ${lib.concatMapStringsSep "\n" (s:
              ''systemctl restart podman-graphide-demo-${s.name}.service || true''
            ) sessionList}
            echo "rebuilt and restarted at $current"
          '';
        };
      })

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

    systemd.timers = lib.mkMerge [
      (lib.mkIf cfg.autoBuild.enable {
        graphide-demo-autobuild = {
          wantedBy = [ "timers.target" ];
          timerConfig = {
            OnCalendar = cfg.autoBuild.interval;
            Persistent = true;
            RandomizedDelaySec = "60";
          };
        };
      })
      (lib.mkIf cfg.recycle.enable (builtins.listToAttrs (map (s:
      lib.nameValuePair "graphide-demo-recycle-${s.name}" {
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnCalendar = cfg.recycle.interval;
          Persistent = false;
          RandomizedDelaySec = "5m";
        };
      }) sessionList)))
    ];
  };
}
