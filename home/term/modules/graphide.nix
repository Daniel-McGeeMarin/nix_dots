{ lib, config, pkgs, inputs, osConfig ? null, flakeAttr ? "XiaNix", ... }:
# Installs gr/grat/gred from the graphide flake input (see flake.nix for why
# it's git+ssh, not github:), and provides `graphide-autoupdate`: one command
# (optionally on a timer) that moves the whole install to the newest RELEASE.
#
# What "newest release" means: the monolith commits
# website/public/releases/latest.json every time CI publishes a release (the
# "release: publish vX manifest" commits). That file names the commit, the
# Linux tarball's file name and its SHA-256. CI has already built that
# tarball (a warm fork-base tree plus a few minutes of packaging) and put it
# in the private Azure container graphidereleases/releases under
# <commit>/graphide-linux-x64.tar.gz. So the update is: read the manifest,
# download that tarball, check its hash, pin the flake input to the same
# commit, switch. No Docker, no compile of the VS Code fork.
#
# History: this used to walk master for the newest commit with a green push
# gate and rebuild the editor from source in a local Docker container (a cold
# ~40 min build every time the fork key changed, because the local Ubuntu
# 22.04 image never matched CI's cache key). Replaced 2026-09-20.
let
  gp = inputs.graphide.packages.${pkgs.stdenv.hostPlatform.system};

  cfg = config.graphide;

  # gred (the editor itself, as opposed to gr/grat): graphide's own
  # packages.gred.src is a pkgs.requireFile pinned to the hash of one
  # specific tarball, which nothing else will substitute for. This override
  # replaces src with the tarball graphide-autoupdate downloaded from CI's
  # release container, so `nix build` works on this machine. It is an
  # absolute path outside the flake, hence `--impure` on every switch.
  gredDistTarball = /home/xia/MyApps/graphide-dist/graphide-linux-x64.tar.gz;
  gred = gp.gred.overrideAttrs (_: { src = gredDistTarball; });

  # The exact nix the rest of the machine runs (Lix, per
  # hosts/*/configuration.nix `nix.package`). Falling back to pkgs.nix would
  # put a second, different client in front of the same daemon for no reason.
  nixPackage = if osConfig != null then osConfig.nix.package else pkgs.nix;

  # Same home-manager the flake is evaluated with, not whatever happens to be
  # in ~/.nix-profile -- an auto-switch must not drift from the checkout it
  # switches.
  homeManagerPackage = inputs.home-manager.packages.${pkgs.stdenv.hostPlatform.system}.home-manager;

  graphideRepo = "GraphideHQ/monolith";
  graphideGitURL = "git+ssh://git@github.com/graphideHQ/monolith";

  autoUpdateScript = pkgs.writeShellApplication {
    name = "graphide-autoupdate";
    runtimeInputs = [
      nixPackage
      homeManagerPackage
      pkgs.gh
      pkgs.jq
      pkgs.git
      pkgs.openssh
      pkgs.azure-cli
      pkgs.util-linux
      pkgs.libnotify
      pkgs.coreutils
    ];
    text = ''
      FLAKE_DIR=${lib.escapeShellArg cfg.autoUpdate.flakeDir}
      FLAKE_ATTR=${lib.escapeShellArg flakeAttr}
      REPO=${lib.escapeShellArg graphideRepo}
      GIT_URL=${lib.escapeShellArg graphideGitURL}
      CHANNEL=${lib.escapeShellArg cfg.autoUpdate.channel}
      MANIFEST_PATH=${lib.escapeShellArg cfg.autoUpdate.manifestPath}
      BLOB_ACCOUNT=${lib.escapeShellArg cfg.autoUpdate.blobAccount}
      BLOB_CONTAINER=${lib.escapeShellArg cfg.autoUpdate.blobContainer}
      GRED_TARBALL=${lib.escapeShellArg (toString gredDistTarball)}
      # Which commit the tarball beside it came from.
      GRED_REV_MARKER="$GRED_TARBALL.built-rev"
      # Written only after a successful `home-manager switch`. "Already up to
      # date" is judged from THIS, not from flake.lock: the lock is rewritten
      # before the switch, so a failed switch would otherwise look finished
      # forever (that is how the old unit sat green on a stale build).
      STATE_DIR="''${XDG_STATE_HOME:-$HOME/.local/state}/graphide-autoupdate"
      SWITCHED_MARKER="$STATE_DIR/switched-rev"

      fail() {
        echo "graphide-autoupdate: $1" >&2
        notify-send -u critical "Graphide update failed" "$1" || true
        exit 1
      }

      # Only guards against two runs of this service overlapping. A manual
      # `homeswitch` in a shell does not take this lock; nix's own profile and
      # store locks are what keep that case honest.
      exec 9>"''${XDG_RUNTIME_DIR:-/tmp}/graphide-autoupdate.lock"
      if ! flock -n 9; then
        echo "graphide-autoupdate: another run holds the lock, skipping"
        exit 0
      fi

      cd "$FLAKE_DIR" || fail "flake directory $FLAKE_DIR is missing"

      current=$(jq -r '.nodes.graphide.locked.rev // empty' flake.lock)
      if [ -z "$current" ]; then
        echo "graphide-autoupdate: flake.lock has no graphide input, nothing to do"
        exit 0
      fi

      # The release manifest on master. Soft-fail if GitHub is unreachable:
      # a red unit on a train would be noise, and the next run retries.
      if ! manifest=$(gh api -H 'Accept: application/vnd.github.raw' \
          "repos/$REPO/contents/$MANIFEST_PATH?ref=master" 2>&1); then
        echo "graphide-autoupdate: could not read the release manifest, will retry: $manifest"
        exit 0
      fi

      release=$(printf '%s' "$manifest" | jq -c --arg c "$CHANNEL" '.channels[$c] // empty')
      [ -n "$release" ] || fail "the release manifest has no '$CHANNEL' channel"
      commit=$(printf '%s' "$release" | jq -r '.commit // empty')
      asset=$(printf '%s' "$release" | jq -r '.assets["linux-x64"] // empty')
      want_sha=$(printf '%s' "$release" | jq -r '.sha256["linux-x64"] // empty')
      version=$(printf '%s' "$release" | jq -r '.version // "?"')
      case "$commit" in
        [0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]*) ;;
        *) fail "the release manifest has no usable commit ('$commit')" ;;
      esac
      [ -n "$asset" ] && [ -n "$want_sha" ] \
        || fail "the release manifest lists no linux-x64 tarball for $commit"

      have_sha=""
      [ -f "$GRED_TARBALL" ] && have_sha=$(sha256sum "$GRED_TARBALL" | cut -d' ' -f1)
      switched=""
      [ -f "$SWITCHED_MARKER" ] && switched=$(cat "$SWITCHED_MARKER")

      if [ "$commit" = "$current" ] && [ "$commit" = "$switched" ] && [ "$have_sha" = "$want_sha" ]; then
        echo "graphide-autoupdate: already on release $version ($commit)"
        exit 0
      fi
      echo "graphide-autoupdate: moving to release $version ($commit)"

      # ── 1. The editor tarball, straight from CI ─────────────────────────────
      if [ "$have_sha" = "$want_sha" ]; then
        echo "graphide-autoupdate: tarball for $commit is already in place"
      else
        tmp=$(mktemp -d)
        trap 'rm -rf "$tmp"' EXIT
        echo "graphide-autoupdate: downloading $commit/$asset from $BLOB_ACCOUNT/$BLOB_CONTAINER ..."
        if ! az storage blob download --account-name "$BLOB_ACCOUNT" \
            --container-name "$BLOB_CONTAINER" --name "$commit/$asset" \
            --file "$tmp/$asset" --auth-mode login --only-show-errors --no-progress >/dev/null; then
          fail "could not download $commit/$asset (is 'az login' still valid?)"
        fi
        got_sha=$(sha256sum "$tmp/$asset" | cut -d' ' -f1)
        [ "$got_sha" = "$want_sha" ] \
          || fail "checksum mismatch for $asset: manifest says $want_sha, downloaded file is $got_sha"
        mkdir -p "$(dirname "$GRED_TARBALL")"
        install -m 0644 "$tmp/$asset" "$GRED_TARBALL.new"
        mv -f "$GRED_TARBALL.new" "$GRED_TARBALL"
      fi
      printf '%s\n' "$commit" > "$GRED_REV_MARKER"

      # ── 2. Pin gr/grat/gred to that same commit ─────────────────────────────
      # One input, one commit: the gred derivation checks the tarball against
      # the tree it is evaluated in, so they must agree. Local only, on
      # purpose: this rewrites flake.lock in the working tree and never
      # commits or pushes it; `git checkout flake.lock` is the whole undo.
      if [ "$commit" != "$current" ]; then
        echo "graphide-autoupdate: re-pinning graphide $current -> $commit"
        nix flake lock --override-input graphide "$GIT_URL?rev=$commit" \
          || fail "could not re-pin flake.lock to $commit"
      fi

      # ── 3. Switch ───────────────────────────────────────────────────────────
      # home-manager builds before it activates, so a broken commit leaves the
      # current generation running and just fails this run. That is the
      # correct outcome -- do not wrap it in a rollback.
      home-manager switch --flake "$FLAKE_DIR#$FLAKE_ATTR" --impure \
        || fail "home-manager switch failed on release $version ($commit)"
      mkdir -p "$STATE_DIR"
      printf '%s\n' "$commit" > "$SWITCHED_MARKER"
      echo "graphide-autoupdate: switched to release $version ($commit)"
    '';
  };
in
{
  options = {
    graphide = {
      enable = lib.mkEnableOption "Enable Graphide (gr, grat, gred)";
      variant = lib.mkOption {
        type = lib.types.enum [ "dev" "prod" ];
        default = "dev";
        description = "Which gr build to install (gr-dev vs gr-prod).";
      };

      autoUpdate = {
        enable = lib.mkEnableOption ''
          a user timer that moves the install to the newest published release
          (downloads CI's tarball, re-pins the graphide flake input to that
          commit, switches home-manager). Separate
          from graphide.enable on purpose: unattended re-installation of the
          editor and CLI you're working in is a materially bigger behaviour
          than having the packages, and should be switchable off on its own
        '';

        interval = lib.mkOption {
          type = lib.types.str;
          default = "30m";
          description = "OnUnitActiveSec for the update timer.";
        };

        flakeDir = lib.mkOption {
          type = lib.types.str;
          default = "${config.home.homeDirectory}/nixos";
          description = "Checkout whose flake.lock is re-pinned and switched.";
        };

        channel = lib.mkOption {
          type = lib.types.str;
          default = "ff";
          description = "Which channel of the release manifest to follow.";
        };

        manifestPath = lib.mkOption {
          type = lib.types.str;
          default = "website/public/releases/latest.json";
          description = ''
            Path, in the monolith repo on master, of the release manifest CI
            commits after every published release. It names the commit, the
            Linux tarball and the tarball's SHA-256.
          '';
        };

        blobAccount = lib.mkOption {
          type = lib.types.str;
          default = "graphidereleases";
          description = "Azure storage account holding the release tarballs (private; read via `az login`).";
        };

        blobContainer = lib.mkOption {
          type = lib.types.str;
          default = "releases";
          description = "Container in blobAccount; tarballs live at <commit>/graphide-linux-x64.tar.gz.";
        };
      };
    };
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      home.packages = [
        (if cfg.variant == "prod" then gp.gr-prod else gp.gr-dev)
        gp.grat
        gred
        # On PATH unconditionally (not gated on autoUpdate.enable) so the
        # timer can stay off and this becomes the manual "update now"
        # command instead. Reads the same cfg.autoUpdate.* options for its
        # defaults either way.
        autoUpdateScript
      ];
    }

    (lib.mkIf cfg.autoUpdate.enable {
      systemd.user.services.graphide-autoupdate = {
        Unit = {
          Description = "Move Graphide (gr, grat, gred) to the newest published release, then switch";
          After = [ "network-online.target" ];
          Wants = [ "network-online.target" ];

          # A `homeswitch` MUST NOT kill a build that is already running.
          #
          # The comment that used to sit here said home-manager never
          # auto-restarts a running service whose definition changed, on the
          # grounds that systemd-activate.sh only PRINTS "Suggested commands:
          # systemctl --user restart ...". That stopped being true when
          # home-manager moved to sd-switch, which runs it. Observed here on
          # 2026-09-12:
          #
          #   23:28:51 Reexecution requested from client PID ('switch-to-confi')
          #   23:28:52 graphide-autoupdate.service: Main process exited,
          #            code=killed, status=15/TERM
          #   23:28:58 Reload requested from client PID ('sd-switch')
          #   23:28:58 Starting Rebuild gred and re-pin gr/grat...
          #
          # Ten minutes into a 34-minute gulp: SIGTERM, then a fresh run that
          # starts the same build again from zero. Five times in the seven
          # days to 2026-09-12 -- this file gets edited often, and every edit
          # changes the unit, so the build is most likely to die exactly when
          # someone is iterating on it.
          #
          # keep-old rather than a timing fix: this is a oneshot driven by a
          # timer, so nothing needs the new definition mid-flight. systemd
          # still reloads the unit file, so the NEXT tick runs the new
          # ExecStart. The only cost is that an edit does not reach a run
          # already in progress, which is the entire point.
          #
          # sd-switch 0.6.2 reads X-SwitchMethod from [Unit]; the accepted
          # values include keep-old, restart, reload, sighup and stop-start.
          X-SwitchMethod = "keep-old";
        };
        Service = {
          Type = "oneshot";
          ExecStart = lib.getExe autoUpdateScript;
          # A nix build should never win a scheduling fight with the editor
          # it is about to replace -- but "never scheduled at all" is not the
          # same as "scheduled last", and idle is the former. The idle I/O
          # class hands this unit the disk only when NOTHING else wants it;
          # on a machine running several agents it can be starved
          # indefinitely, and nix evaluation is almost pure
          # small-file I/O, so it is the worst possible workload to put there.
          #
          # Measured on 2026-09-12: the 19:56 run took 2h49m of wall clock and
          # consumed 36 SECONDS of CPU. It was not working, it was blocked --
          # 44 min for the first flake eval, then 2h01m for home-manager's
          # post-activation `news` eval, with a 3-minute derivation build in
          # between. It holds the flock throughout, so it also blocks every
          # later cycle behind it.
          #
          # best-effort 7 is the lowest non-idle priority: still behind
          # anything interactive, but guaranteed forward progress.
          Nice = 10;
          IOSchedulingClass = "best-effort";
          IOSchedulingPriority = 7;
          # Default TimeoutStartSec (90s) would kill a cold home-manager
          # evaluation and switch. The download itself is a ~170 MB fetch.
          TimeoutStartSec = "2h";
        };
      };

      systemd.user.timers.graphide-autoupdate = {
        Unit.Description = "Check for a newer published Graphide release";
        Timer = {
          # OnStartupSec, not OnBootSec: this is a user manager, and the
          # first check should land shortly after login rather than after a
          # full interval. Both these and OnUnitActiveSec are
          # CLOCK_BOOTTIME, so a suspended laptop catches up on wake rather
          # than losing the cycle.
          OnStartupSec = "5m";
          OnUnitActiveSec = cfg.autoUpdate.interval;
          RandomizedDelaySec = "2m";
          Persistent = true;
        };
        Install.WantedBy = [ "timers.target" ];
      };
    })
  ]);
}
