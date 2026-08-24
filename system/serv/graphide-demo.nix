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

  # Whether this host makes the patched browser server itself, or expects to
  # find one. A localhost/ tag cannot come from anywhere else, so it is also
  # the switch for the unit that builds it. Point forkServerImage at a registry
  # and that unit simply does not exist.
  localForkServer = lib.hasPrefix "localhost/" cfg.forkServerImage;

  sessionDir = s: "${cfg.stateDir}/${s.name}";

  # Without these the database, the workspace and the IDE's settings live in the
  # container's writable layer, which oci-containers discards on every restart.
  # Extensions are deliberately not persisted: the entrypoint reinstalls the
  # extension each boot so a rebuilt image actually takes effect, and they live
  # in /opt/codium-data/extensions, a sibling of the mount below rather than
  # inside it.
  #
  # The IDE mount is at .../server and not at the User directory it is actually
  # there to keep, which matters. podman materialises any missing parent of a
  # mount point inside the container itself, and it creates them root-owned
  # 0755 — after the image's build-time `chown -R demo:demo /opt/codium-data`
  # has already run, so nothing corrects them. The pod then runs as demo
  # (uid 1000). Mounting at server/data/User left server/ and server/data/
  # root-owned, and the entrypoint's `mkdir -p` of server/data/logs, a sibling
  # of the mount, died with EACCES; because that script is set -e, one
  # unwritable directory took down all three pods. Traversal still worked, so
  # the User mount itself looked fine and the failure surfaced somewhere else
  # entirely.
  #
  # /opt/codium-data does exist in the image and is owned by demo, so mounting
  # one level down at server/ is the deepest point that requires podman to
  # invent nothing. Going deeper just moves the same bug down a level.
  volumesFor = s: lib.optionals cfg.persist [
    "${sessionDir s}/data:/data"
    "${sessionDir s}/workspace:/workspace"
    "${sessionDir s}/codium:/opt/codium-data/server"
  ] ++ lib.optional (cfg.seedDir != null) "${cfg.seedDir}:/seed:ro";

  containerFor = s: lib.nameValuePair "graphide-demo-${s.name}" {
    # `sessions` stays a plain list of names because the name IS the subdomain
    # and everything else about a box is derived from its index. This is the
    # one dimension a box is allowed to differ in, and it exists so a patched
    # editor build can be tried on one box while the others keep the stock one.
    image = cfg.imageFor.${s.name} or cfg.image;
    # Loopback only. Caddy reaches it; nothing else on the network can.
    ports = [ "127.0.0.1:${toString s.port}:8000" ];
    volumes = volumesFor s;
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
  #
  # Two gates in series, because they answer different questions. Authelia
  # proves WHO you are; it has no opinion on how many people are already on a
  # box. The second forward_auth, to website-api's /api/demo/gate, enforces
  # that only one of you is on a given box at a time — which is a correctness
  # requirement, not a nicety: a pod is single-workspace and grug's HTTP
  # surface has no auth at all, so two guests on one pod share the same graph,
  # the same files, the same agent session and the same shell (see the module
  # header). The gate identifies the caller from the Remote-User header that
  # require_auth's `copy_headers` has already added to the request by the time
  # the second forward_auth runs, which is why the order of these two lines is
  # not interchangeable.
  #
  # New dependency, worth stating plainly: the demo pods now depend on
  # website-api being up. forward_auth treats an unreachable upstream as a
  # failure, so if podman-website-api is down every demo box answers 502 even
  # though the pods themselves are fine. Check `systemctl status
  # podman-website-api` before debugging a pod that will not load.
  vhostFor = s: lib.nameValuePair "http://${s.name}.${cfg.domain}" {
    extraConfig = ''
      import require_auth
      forward_auth 127.0.0.1:8010 {
        uri /api/demo/gate?box=${s.name}
      }
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

    persist = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Keep each session's database, workspace and editor settings across
        restarts by mounting them from stateDir.

        Off by default because it gives up the property that made handing out
        a link acceptable: with ephemeral pods, a restart is what expires a
        guest's access to whatever they did, and the next visitor cannot see
        it. Persisting means anything one guest leaves in the workspace — or
        any credential they paste into a file — is there for the next.

        Also disable recycle.enable, or the hourly restart still runs and the
        only thing persistence buys is a slower boot.
      '';
    };

    stateDir = lib.mkOption {
      type = lib.types.str;
      default = "/srv/data/graphide-demo/sessions";
      description = "Parent of the per-session state directories.";
    };

    seedDir = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "/srv/data/graphide-demo/seed";
      description = ''
        A project to open instead of an empty workspace, bind-mounted
        read-only and copied in on first boot. Host-side rather than baked
        into the image so changing the demo project needs no rebuild, and so
        the project need not be committed to either source repo.

        Copy it in with rsync and exclude the heavy build artefacts:
          rsync -a --delete --exclude node_modules --exclude .next \
            ~/project/ root@host:/srv/data/graphide-demo/seed/
      '';
    };

    allowedGroups = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "demo" "admins" ];
      description = ''
        Authelia groups admitted to the pods. Load-bearing: an access_control
        rule with no subject admits every authenticated user, so without this
        a guest account created for a demo would also reach everything else
        behind this SSO. Listed groups are OR'd.
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

    imageFor = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      example = { demobox1 = "localhost/graphide-demo:fork"; };
      description = ''
        Per-session image, keyed by session name. A session not named here uses
        `image`.

        The demo images differ in exactly one thing: which browser server they
        carry. `:latest` is stock VSCodium; `:fork` is gred's own build with
        patches/ applied, which is the only way to see the Graphide title bar,
        the Home/File/Edit/Advanced menu bar, page mode and the reserved-canvas
        guarantees in a browser. Both are built on every cycle, so moving a box
        between them is a config change and not a rebuild.
      '';
    };

    forkImage = lib.mkOption {
      type = lib.types.str;
      default = "localhost/graphide-demo:fork";
      description = ''
        The local tag autoBuild.buildFork promotes. Point `imageFor` entries at
        this.
      '';
    };

    forkServerImage = lib.mkOption {
      type = lib.types.str;
      default = "localhost/graphide-reh-web:fork";
      description = ''
        The compiled patched browser server, passed to the pod build as
        SERVER_IMAGE.

        A LOCAL tag by default, because that is how everything else in this
        service works: autoBuild clones both repos and builds the pod and the
        extension image on this host, and pulls nothing. Making this one an
        exception would put a registry, a credential and an outage mode into
        the only path here that currently has none.

        It is not built by the autobuild either, because compiling reh-web is a
        35-55 minute VS Code build and has no business inside a five-minute
        timer. It is populated once, out of band, and only re-made when
        gred/patches, product.json or branding change:

          nix run .#gred-web                       # in a monolith checkout
          podman build -f <gred>/build/reh-web-image.Dockerfile --target fork \
            -t localhost/graphide-reh-web:fork \
            ~/.cache/graphide/vscode-reh-web-linux-x64

        Set it to a ghcr.io reference on a host that would rather pull one.
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

      forkServerTimeout = lib.mkOption {
        type = lib.types.str;
        default = "180min";
        description = ''
          How long the patched-server build is allowed to take. It is a full VS
          Code compile - 35-55 minutes on a good machine - and it runs in its
          own unit rather than inside the five-minute autobuild timer, which is
          the only reason that timer stays five minutes.
        '';
      };

      buildFork = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Also build and promote `forkImage` on every cycle: the same pod, with
          the patched browser server instead of the stock one.

          Cheap. The patched server is pulled as a prebuilt layer, so the
          second build is a handful of COPYs on top of an image the first build
          already produced, and it reuses that build's extension image rather
          than re-running npm ci. Both tags are promoted together or neither
          is, so the boxes never run a half-updated pair.
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
      {
        # A key that matches no session does nothing whatsoever: the box you
        # meant to move stays on the default image and nothing says so.
        assertion = lib.all (n: lib.elem n cfg.sessions) (lib.attrNames cfg.imageFor);
        message = ''
          serv.graphide-demo.imageFor names sessions that are not in `sessions`:
          ${toString (lib.subtractLists cfg.sessions (lib.attrNames cfg.imageFor))}
        '';
      }
      {
        assertion = !(lib.any (v: v == cfg.forkImage) (lib.attrValues cfg.imageFor))
                    || cfg.autoBuild.buildFork
                    || !cfg.autoBuild.enable;
        message = ''
          serv.graphide-demo has a session pinned to forkImage
          (${cfg.forkImage}) but autoBuild.buildFork is false, so nothing ever
          builds that tag and the container will fail to start.
        '';
      }
    ];

    warnings = lib.optional (cfg.persist && cfg.recycle.enable) ''
      serv.graphide-demo has both persist and recycle.enable set. The hourly
      restart still happens, so state survives it and the only effect of
      recycling is a slower boot. Set recycle.enable = false.
    '';

    # 1000 is the demo user inside the image. Rootful podman without a userns
    # remap means container UID 1000 is host UID 1000, so the container can only
    # write these if they are owned by that number.
    systemd.tmpfiles.rules =
      lib.optionals cfg.persist
        ([ "d ${cfg.stateDir} 0750 root root -" ]
         ++ lib.concatMap (s: [
           "d ${sessionDir s}           0750 1000 1000 -"
           "d ${sessionDir s}/data      0700 1000 1000 -"
           "d ${sessionDir s}/workspace 0750 1000 1000 -"
           # Owned by 1000 so that everything codium-server creates beneath it
           # inherits a writable parent; see the mount note on volumesFor.
           "d ${sessionDir s}/codium    0750 1000 1000 -"
         ]) sessionList)
      # Read-only to the pods, so root can own it and a guest cannot edit the
      # project every later pod is seeded from.
      ++ lib.optional (cfg.seedDir != null) "d ${cfg.seedDir} 0755 root root -";

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
      # The patched browser server, built here like everything else.
      #
      # Its own unit, not a step in the autobuild, for one reason: this is a
      # full VS Code compile and the autobuild runs every five minutes. Nothing
      # waits on it - the autobuild starts it with --no-block when it notices
      # the image is missing or stale, ships the stock pod as usual, and picks
      # the new server up on a later cycle.
      #
      # Idempotent by patch hash, carried as a LABEL on the image it produces.
      # A label travels with the image, so this cannot be fooled by a stamp file
      # that outlived the thing it described.
      (lib.mkIf (cfg.autoBuild.enable && cfg.autoBuild.buildFork && localForkServer) {
        graphide-demo-fork-server = {
          description = "Build the patched Graphide browser server (full VS Code compile)";
          after = [ "network-online.target" ];
          wants = [ "network-online.target" ];
          path = with pkgs; [
            bash git podman coreutils gnutar gzip gnugrep gnused findutils
            nodejs_22 python3 gcc gnumake pkg-config
            krb5 xorg.libxkbfile libsecret
          ];
          serviceConfig = {
            Type = "oneshot";
            TimeoutStartSec = cfg.autoBuild.forkServerTimeout;
          };
          script = let
            webLibs = with pkgs; [ krb5 xorg.libxkbfile libsecret ];
            pcPath  = with pkgs; [ krb5 xorg.libxkbfile xorg.xorgproto libsecret glib ];
          in ''
            set -euo pipefail

            gred="${cfg.autoBuild.srcDir}/gred"
            if [ ! -d "$gred/build" ]; then
              echo "no gred checkout at $gred yet; the autobuild clones it - try again after a cycle" >&2
              exit 1
            fi

            want="$(${lib.getExe pkgs.bash} "$gred/build/prepare-src.sh" --hash-only)"
            have="$(podman image inspect --format '{{index .Labels "graphide.patch-hash"}}' \
                     "${cfg.forkServerImage}" 2>/dev/null || true)"

            if [ "$want" = "$have" ]; then
              echo "patched server is already current ($want)"
              exit 0
            fi
            echo "building the patched server; have=''${have:-none} want=$want"

            # node-gyp reads these and runtimeInputs only sets PATH. xorgproto
            # puts kbproto.pc under share/pkgconfig, and libxkbfile.pc requires
            # it - that one is why the search path has two halves.
            export LD_LIBRARY_PATH="${lib.makeLibraryPath webLibs}''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
            export PKG_CONFIG_PATH="${lib.makeSearchPathOutput "dev" "lib/pkgconfig" pcPath}:${lib.makeSearchPath "share/pkgconfig" [ pkgs.xorg.xorgproto ]}"
            export C_INCLUDE_PATH="${lib.makeSearchPathOutput "dev" "include" webLibs}"
            export CPLUS_INCLUDE_PATH="$C_INCLUDE_PATH"

            # SKIP_TARBALL: the tree is wrapped in an image below, so packaging
            # it as well is a few hundred MB of nothing on this disk.
            export BUILD_DIR="${cfg.autoBuild.srcDir}/vscode-src"
            export SKIP_TARBALL=1
            ${lib.getExe pkgs.bash} "$gred/build/build-web.sh"

            tree="${cfg.autoBuild.srcDir}/vscode-reh-web-linux-x64"
            test -x "$tree/bin/graphide-server"

            podman build --network=host \
              -f "$gred/build/reh-web-image.Dockerfile" --target fork \
              --label "graphide.patch-hash=$want" \
              -t "${cfg.forkServerImage}" "$tree"

            echo "patched server tagged ${cfg.forkServerImage} ($want)"

            # The pod that consumes it is the autobuild's business; nudge it
            # rather than duplicating the pod build in here.
            ${pkgs.systemd}/bin/systemctl start --no-block graphide-demo-autobuild.service || true
          '';
        };
      })

      (lib.mkIf cfg.autoBuild.enable {
        graphide-demo-autobuild = {
          description = "Rebuild the Graphide demo pod when its sources change";
          # No ghcr-login dependency: forkServerImage defaults to a local tag
          # and this unit builds everything else from git. A host that points
          # it at a registry needs to add that ordering itself.
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
            pkgs.systemd
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

            sync_repo "${cfg.autoBuild.monolithUrl}" "${src}/monolith" "${monoBranch}" >/dev/null
            sync_repo "${cfg.autoBuild.gredUrl}"     "${src}/gred"     "${gredBranch}" >/dev/null

            # The last commit that touched anything this IMAGE is built from,
            # rather than the repo tip.
            #
            # The tip is what this used to use, and it meant a docs commit, a
            # bench yaml or a README typo in either repo triggered a cold CGO
            # rebuild of grug plus two image builds, every five minutes, on the
            # machine that serves the demos.
            #
            # The monolith list mirrors demo-pod.yml's own push filter. When
            # you add a path there, add it here - they will not warn you.
            rev_for() {  # <dir> <branch> <path>...
              local dir="$1" branch="$2"; shift 2
              local r
              r="$(git -C "$dir" log -1 --format=%H "$branch" -- "$@" 2>/dev/null || true)"
              # Empty means no commit in this history ever touched those paths,
              # which in practice means the path list is wrong. Returning it
              # would make every later comparison equal and the boxes would
              # silently never rebuild again, so this is fatal rather than
              # tolerated.
              if [ -z "$r" ]; then
                echo "FATAL: no commit in $dir touches: $*" >&2
                echo "  The path list in graphide-demo.nix is wrong. Refusing to" >&2
                echo "  build, because an empty revision would pin the stamp forever." >&2
                # `return`, not `exit`: this runs inside $( ), where exit would
                # only end the subshell. set -e would still abort on the failed
                # assignment, but only by accident - the explicit `|| exit 1`
                # below is what actually guarantees it.
                return 1
              fi
              printf '%s' "$r"
            }

            # Note the gred list has no patches/ or product.json in it, on
            # purpose. A patch change does not change what is IN this image; it
            # changes the server image, and that is what server_digest below
            # tracks. Listing them here would rebuild the pod for something it
            # does not contain.
            mono_rev=$(rev_for "${src}/monolith" "${monoBranch}" \
              deploy/demo-pod grug server/api server/router shared agents go.work go.work.sum) || exit 1
            gred_rev=$(rev_for "${src}/gred" "${gredBranch}" \
              extensions/graphide build/ext-image.Dockerfile build/reh-web-stock.Dockerfile) || exit 1

            # The patched server arrives as an image rather than as source, so
            # a change to it is an input neither revision above can see. Its id
            # is part of the stamp so a rebuilt one ships.
            #
            # have_fork gates the whole fork half. A host that has not made the
            # server yet is the NORMAL state on a fresh install, and it must not
            # stop demobox2 and demobox3 from updating - which is exactly what
            # an unguarded `set -e` build failure here would do, since promotion
            # happens after both builds.
            server_digest=none
            have_fork=0
            ${lib.optionalString cfg.autoBuild.buildFork ''
              # Only try the network for a registry reference. A local tag is
              # made by hand and a pull would just be a slow failure.
              case "${cfg.forkServerImage}" in
                localhost/*|"") : ;;
                *) podman pull -q "${cfg.forkServerImage}" >/dev/null 2>&1 || true ;;
              esac
              server_label="$(podman image inspect --format '{{index .Labels "graphide.patch-hash"}}' \
                                "${cfg.forkServerImage}" 2>/dev/null || true)"
              want_label="$(${lib.getExe pkgs.bash} "${src}/gred/build/prepare-src.sh" --hash-only 2>/dev/null || echo unknown)"

              have_desc="$server_label"
              [ -n "$have_desc" ] || have_desc=none

              if [ -n "$server_label" ] && [ "$server_label" = "$want_label" ]; then
                server_digest="$server_label"
                have_fork=1
              else
                ${lib.optionalString localForkServer ''
                  # Missing or stale. Kick the builder and carry on: it is a
                  # full VS Code compile and this unit runs every five minutes,
                  # so waiting on it here would wedge the stock pod behind it.
                  echo "patched server needs building (have=$have_desc want=$want_label); starting graphide-demo-fork-server" >&2
                  ${pkgs.systemd}/bin/systemctl start --no-block graphide-demo-fork-server.service || true
                ''}
                ${lib.optionalString (!localForkServer) ''
                  echo "WARNING: ${cfg.forkServerImage} is absent or stale and is not built here." >&2
                ''}
                server_digest="stale-or-absent"
                echo "         The :fork pod is skipped this cycle; the stock pod still ships." >&2
              fi
            ''}

            # v2 because the stamp format changed; bumping it forces exactly
            # one rebuild everywhere rather than leaving boxes on a stamp that
            # can no longer match.
            current="v2-$mono_rev-$gred_rev-$server_digest"

            stamp="${src}/.last-built"

            # Narrowing the trigger means a change to a path not listed above
            # never ships, and unlike a GitHub workflow this host has no "Run
            # workflow" button. Touch this file to force one cycle.
            if [ -f "${src}/.force-rebuild" ]; then
              rm -f "${src}/.force-rebuild"
              echo "forced rebuild"
            elif [ -f "$stamp" ] && [ "$(cat "$stamp")" = "$current" ]; then
              echo "no change since last build ($current)"
              exit 0
            fi

            echo "building $current"
            # Staging tag: promoted only on success, so the running pods keep
            # whatever last worked if this build fails.
            #
            # Absolute store path, not `bash` on PATH: a systemd unit's PATH
            # is only what this module lists, and grepping ExecStart cannot
            # tell you whether `path` changed — that hash is the script body
            # alone. Pinning the interpreter here makes the next missing-tool
            # failure a missing file in the closure, not a 127 in the journal.
            staging="localhost/graphide-demo:building"
            TAG="$staging" VARIANT=stock GRED_DIR="${src}/gred" \
              ${lib.getExe pkgs.bash} "${src}/monolith/deploy/demo-pod/build-local.sh"

            ${lib.optionalString cfg.autoBuild.buildFork ''
              if [ "$have_fork" = 1 ]; then
                # SKIP_EXT: the stock build above already produced the extension
                # image from this same checkout. Rebuilding it would re-run
                # npm ci for a byte-identical result.
                staging_fork="localhost/graphide-demo:building-fork"
                TAG="$staging_fork" VARIANT=fork SKIP_EXT=1 \
                  FORK_SERVER_IMAGE="${cfg.forkServerImage}" GRED_DIR="${src}/gred" \
                  ${lib.getExe pkgs.bash} "${src}/monolith/deploy/demo-pod/build-local.sh"
              fi
            ''}

            # Promoted together, so the boxes never run a half-updated pair:
            # demobox1 on a new fork while 2 and 3 sit on an old latest, with
            # nothing recording which combination is live. Note this is reached
            # only if every build above succeeded - a fork build that FAILS
            # still blocks the stock promote, on purpose. A fork server that is
            # merely ABSENT is the different case, handled above.
            podman tag "$staging" "${cfg.image}"
            ${lib.optionalString cfg.autoBuild.buildFork ''
              if [ "$have_fork" = 1 ]; then
                podman tag "$staging_fork" "${cfg.forkImage}"
              fi
            ''}
            echo "$current" > "$stamp"

            ${lib.concatMapStringsSep "\n" (s:
              ''${pkgs.systemd}/bin/systemctl restart podman-graphide-demo-${s.name}.service || true''
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
        subject = map (g: "group:${g}") cfg.allowedGroups;
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
