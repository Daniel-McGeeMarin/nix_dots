{ lib, config, pkgs, inputs, osConfig ? null, flakeAttr ? "XiaNix", ... }:
# Installs gr/grat/gred from the graphide flake input (see flake.nix for why
# it's git+ssh, not github:), and optionally a user timer that re-pins that
# input to the newest green master commit and switches home-manager onto it
# -- so the installed editor/CLI tracks the monolith without anyone asking.
# Ported from BenMac31/nixdots (commit 8884187f8, "feat(graphide): auto-
# update to the newest green master commit on a timer") and adapted to this
# repo's layout; see that commit for the fuller original rationale.
let
  gp = inputs.graphide.packages.${pkgs.stdenv.hostPlatform.system};
  # gred comes from its own input so a failed editor build cannot hold the
  # CLI and daemon back; see the `graphide-gred` comment in flake.nix.
  gpGred = inputs.graphide-gred.packages.${pkgs.stdenv.hostPlatform.system};

  cfg = config.graphide;

  # gred (the editor itself, as opposed to gr/grat) has no published release
  # build -- graphide's own flake.nix says so directly: "release CI is out of
  # scope". packages.gred.src is a pkgs.requireFile pinned to whatever exact
  # tarball hash the last person who ran the Docker release build got, and
  # nothing else will substitute for it.
  #
  # That pin will not match a fresh build (tarballs aren't byte-reproducible:
  # timestamps, archive ordering), so `nix build` on this hash always 404s
  # for everyone who hasn't personally run the release build and had it land
  # on that exact hash by luck. This override replaces gred's src with a
  # locally-built artifact instead of graphide's pin, so `nix build` actually
  # works on this machine.
  #
  # Consequence worth knowing: this ties gred to whatever commit it was last
  # built against. graphide.autoUpdate's timer keeps this current on its own
  # (see autoUpdateScript below, which runs graphide-rebuild-gred against a
  # dedicated clean clone before every switch) -- graphide-rebuild-gred only
  # needs to be run by hand for an out-of-cycle rebuild, e.g. right after
  # pulling gred changes you want installed before the next timer tick.
  gredDistTarball = /home/xia/MyApps/graphide-dist/graphide-linux-x64.tar.gz;
  gred = gpGred.gred.overrideAttrs (_: { src = gredDistTarball; });

  rebuildGredScript = pkgs.writeShellApplication {
    name = "graphide-rebuild-gred";
    # NOT pkgs.docker: that specific nixpkgs version is marked insecure and
    # refuses to evaluate. Not needed anyway -- this machine already has a
    # working `docker` on PATH (virtualisation.docker), so this just uses
    # that rather than declaring a second, nix-packaged one.
    runtimeInputs = [ pkgs.git pkgs.coreutils ];
    text = ''
      # Rebuilds gred's release tarball from a local graphide checkout and
      # drops it where graphide.nix's override picks it up. Run this after
      # pulling gred changes you actually want installed -- see the
      # gredDistTarball comment in graphide.nix for why this can't just
      # happen automatically on a timer the way gr/grat do.
      #
      # Usage: graphide-rebuild-gred [path-to-monolith-checkout]
      # Defaults to the checkout the `a` alias cds into.
      MONOLITH_DIR="''${1:-$HOME/Documents/startup/Graphide/monolith}"
      [ -d "$MONOLITH_DIR/gred" ] || {
        echo "graphide-rebuild-gred: $MONOLITH_DIR doesn't look like a graphide checkout (no gred/)" >&2
        exit 1
      }

      CACHE_ROOT="$HOME/.cache/graphide"
      # Per-fork-key build trees. Each key gets its OWN parent directory,
      # because gulp writes its packaged output as a SIBLING of BUILD_DIR
      # (build-release.sh looks for "$(dirname "$BUILD_DIR")"/VSCode-linux-*),
      # so two keys sharing a parent would fight over one output directory.
      TREES_ROOT="$CACHE_ROOT/release-trees"
      KEEP_TREES=2

      WORK="$(mktemp -d)"
      # One named container, removed before a new one starts and removed when
      # this script dies. `docker run --rm` alone does NOT stop the container
      # when the client is killed: on 2026-09-12 the timer's timeout killed two
      # launchers and left two 4 GB gulp builds of the same commit compiling
      # under containerd for over an hour each, with a third started on top.
      CONTAINER=graphide-autobuild
      trap 'docker rm -f "$CONTAINER" >/dev/null 2>&1 || true; rm -rf "$WORK"' EXIT TERM INT
      docker rm -f "$CONTAINER" >/dev/null 2>&1 || true

      echo "[1/5] Building Go binaries (grug, gr, grach) + bwrap in a stock-glibc container ..."
      # The monolith moved every shell script under utilities/scripts/ on
      # 2026-09-14. A hard-coded path that quietly stops existing is exactly
      # how gred froze here: from 2026-09-13 every timer cycle died on
      # "scripts/build-dist-container.sh: No such file or directory", left the
      # pin on the previous build, and that older tree's stale vendor hash then
      # failed every home-manager switch on the machine. Try the new path, fall
      # back to the old one so an older checkout still builds, and say which is
      # missing rather than letting bash report it.
      dist_builder="$MONOLITH_DIR/utilities/scripts/build-dist-container.sh"
      [ -f "$dist_builder" ] || dist_builder="$MONOLITH_DIR/scripts/build-dist-container.sh"
      [ -f "$dist_builder" ] || {
        echo "graphide-rebuild-gred: no build-dist-container.sh under $MONOLITH_DIR (looked in utilities/scripts/ and scripts/)" >&2
        exit 1
      }
      bash "$dist_builder" linux amd64 "$WORK/bins"

      echo "[2/5] Building the release image ..."
      # Only the tarball is consumed here (packages.gred wraps it); the
      # AppImage step needs mksquashfs, which the build image lacks, and on
      # 2026-09-12 that made every otherwise-successful hour-long build
      # count as failed and the timer redo it each cycle.
      docker build -t graphide-build-env -f "$MONOLITH_DIR/gred/build/Dockerfile" "$MONOLITH_DIR/gred"
      mkdir -p "$TREES_ROOT"

      # ── The build tree has to live in the bind mount, and be keyed ──────────
      #
      # This used to pass no BUILD_DIR at all, and the comment above the docker
      # run claimed it "reuses the npm/build cache under ~/.cache/graphide".
      # It did not. build-release.sh derives
      #   BUILD_DIR=''${XDG_CACHE_HOME:-$HOME/.cache}/graphide/vscode-src
      # and this container sets HOME=/tmp, so the tree landed on
      # /tmp/.cache/graphide/vscode-src -- inside the container's own
      # filesystem, NOT the bind mount beside it -- and `--rm` deleted it on
      # exit. Every single rebuild was therefore a cold build: a fresh
      # prepare-src, a fresh npm install of ~1580 packages, fresh native module
      # compiles and a full 34-minute gulp, all thrown away afterwards.
      # Confirmed on 2026-09-13 by inspecting a live build container.
      #
      # Setting BUILD_DIR explicitly is the fix, and it is also what makes the
      # cache key below mean anything: with no persistent tree there is nothing
      # for GRAPHIDE_REUSE_TREE to reuse.
      #
      # The key is computed INSIDE the build image rather than on the host.
      # fork-key.sh folds in `node --version`, node's ABI number and `uname
      # -sm`, which describe the toolchain the native modules are compiled
      # against; a host node of a different version would produce a key that
      # does not describe the tree the container actually builds. Same reason
      # desktop-release.yml keys on the runner image.
      FORK_KEY="$(docker run --rm \
        -u "$(id -u):$(id -g)" \
        -v "$MONOLITH_DIR":"$MONOLITH_DIR" \
        -e HOME=/tmp \
        graphide-build-env \
        bash -c "cd '$MONOLITH_DIR/gred' && bash build/fork-key.sh linux-x64" 2>/dev/null | tail -n 1)"

      REUSE=0
      if [ -z "$FORK_KEY" ]; then
        # Never guess. A missing key means a cold build into a fixed directory
        # that is never reused, not a heuristic hit -- build-release.sh's own
        # comment is the rule here: the failure mode of guessing wrong is an
        # artifact that launches, works, and contains the wrong code.
        echo "graphide-rebuild-gred: could not compute a fork key; cold build, no reuse" >&2
        FORK_KEY=nokey
      fi
      TREE_PARENT="$TREES_ROOT/$FORK_KEY"
      BUILD_DIR="$TREE_PARENT/vscode-src"

      # Reuse only on all three: the completion marker, the source tree, and
      # the packaged output beside it. build-release.sh hard-fails when
      # GRAPHIDE_REUSE_TREE=1 and the gulp output is missing, which is correct
      # but is a failed timer cycle; checking here turns that into a cache miss.
      if [ "$FORK_KEY" != nokey ] && [ -f "$TREE_PARENT/.complete" ] && [ -d "$BUILD_DIR" ]; then
        for d in "$TREE_PARENT"/VSCode-linux-*; do
          [ -d "$d" ] && REUSE=1
        done
      fi

      if [ "$REUSE" = 1 ]; then
        echo "[3/5] Fork key ''${FORK_KEY:0:12}: HIT -- packaging the cached tree (skips npm install and gulp) ..."
      else
        echo "[3/5] Fork key ''${FORK_KEY:0:12}: MISS -- full build (npm install + gulp, ~40 min) ..."
      fi
      # Backgrounded and waited on, not run in the foreground: bash runs a
      # signal trap only after the foreground command returns, so a
      # foreground `docker run` would make the TERM from a systemd stop wait
      # for the whole build. With `wait`, TERM interrupts the wait, the trap
      # removes the container, and the build actually stops.
      docker run --rm --name "$CONTAINER" \
        --memory 12g --memory-swap 12g --cpus 12 \
        -u "$(id -u):$(id -g)" \
        -v "$CACHE_ROOT":"$CACHE_ROOT" \
        -v "$MONOLITH_DIR":"$MONOLITH_DIR" \
        -v "$WORK/bins":"$WORK/bins" \
        -e HOME=/tmp \
        -e BUILD_DIR="$BUILD_DIR" \
        -e MONOREPO_DIR="$MONOLITH_DIR" \
        -e GRAPHIDE_SKIP_APPIMAGE=1 \
        -e GRAPHIDE_REUSE_TREE="$REUSE" \
        -e GRAPHIDE_GO_BIN_DIR="$WORK/bins" \
        graphide-build-env bash "$MONOLITH_DIR/gred/build/build-release.sh" linux-x64 &
      wait $!

      # Only after the build actually returned 0. The marker is what the next
      # run tests, so writing it earlier would lock in a half-built tree.
      if [ "$FORK_KEY" != nokey ]; then
        touch "$TREE_PARENT/.complete"
      fi

      echo "[4/5] Installing the tarball ..."
      mkdir -p "$HOME/MyApps/graphide-dist"
      cp "$MONOLITH_DIR/gred/dist/graphide-linux-x64.tar.gz" "$HOME/MyApps/graphide-dist/graphide-linux-x64.tar.gz"

      # ── Prune ──────────────────────────────────────────────────────────────
      #
      # Each tree is roughly 5 GB (checkout + node_modules + out-build +
      # packaged output). Nothing has ever pruned this cache directory, which
      # is how it reached 48 GB with ten stale 3 GB copies in it, so a cache
      # that now creates a directory per key has to clean up after itself.
      # Keep the newest two: the current key, and the one before it, so a key
      # that flips back and forth still hits.
      echo "[5/5] Pruning release trees, keeping the newest $KEEP_TREES ..."
      for d in "$TREES_ROOT"/*; do
        [ -d "$d" ] || continue
        printf '%s %s\n' "$(stat -c %Y "$d")" "$d"
      done | sort -rn | cut -d' ' -f2- | tail -n +$((KEEP_TREES + 1)) | while IFS= read -r old_tree; do
        echo "  pruning $(basename "$old_tree")"
        rm -rf "$old_tree"
      done

      echo "Done. Run 'homeswitch' to rebuild gred against the new tarball."
    '';
  };

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
  # Same repo, as a plain git URL `git clone`/`git fetch` understand -- the
  # git+ssh:// scheme above is nix's flake-input syntax, not a URL a bare git
  # command accepts.
  graphideCloneURL = "ssh://git@github.com/graphideHQ/monolith";

  autoUpdateScript = pkgs.writeShellApplication {
    name = "graphide-autoupdate";
    runtimeInputs = [
      nixPackage
      homeManagerPackage
      pkgs.gh
      pkgs.jq
      pkgs.git
      pkgs.openssh
      pkgs.util-linux
      pkgs.libnotify
      pkgs.coreutils
      # So `graphide-rebuild-gred` (below) is just a name on PATH here, same
      # as it is in an interactive shell. docker itself is deliberately NOT
      # in this list -- see the comment on rebuildGredScript for why -- and
      # is picked up from the ambient PATH NixOS gives every systemd unit
      # (/run/current-system/sw/bin), same as a manual run would find it.
      rebuildGredScript
    ];
    text = ''
      FLAKE_DIR=${lib.escapeShellArg cfg.autoUpdate.flakeDir}
      FLAKE_ATTR=${lib.escapeShellArg flakeAttr}
      REPO=${lib.escapeShellArg graphideRepo}
      WORKFLOW=${lib.escapeShellArg cfg.autoUpdate.workflow}
      GIT_URL=${lib.escapeShellArg graphideGitURL}
      CLONE_URL=${lib.escapeShellArg graphideCloneURL}
      GRED_SRC_DIR=${lib.escapeShellArg cfg.autoUpdate.gredBuildDir}
      # Sidecar next to the tarball itself, recording which commit it was
      # actually built from -- see the "already up to date" check below for
      # why this has to be tracked separately from flake.lock's pin.
      GRED_REV_MARKER=${lib.escapeShellArg "${toString gredDistTarball}.built-rev"}

      fail() {
        echo "graphide-autoupdate: $1" >&2
        notify-send -u critical "Graphide auto-update failed" "$1" || true
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
      # gred's own pin; advances only after a build succeeded at that commit.
      gred_current=$(jq -r '.nodes."graphide-gred".locked.rev // empty' flake.lock)

      # Soft-fail on anything that is just the network or GitHub being
      # unavailable: the timer comes back in ${cfg.autoUpdate.interval}, and a
      # red unit every cycle on a train would be noise, not information.
      # Depot CI is the gate, and it does NOT appear in the Actions API --
      # `gh run list` stopped seeing "push gate" when CI moved to Depot, which
      # left this timer pinned to a 2026-09-08 commit for four days. Depot
      # reports as CHECK RUNS on each commit from the app `depot-code-access`,
      # named "<workflow> / <job>" (same reading as monolith's
      # scripts/ci-status.sh). Walk master newest-first and take the first
      # commit where the workflow posted checks and every one succeeded. A
      # commit with none is skipped: push gate is path-filtered.
      if ! shas=$(gh api "repos/$REPO/commits?sha=master&per_page=40" --jq '.[].sha' 2>&1); then
        echo "graphide-autoupdate: gh lookup failed, will retry next cycle: $shas"
        exit 0
      fi

      green=""
      for sha in $shas; do
        if ! checks=$(gh api "repos/$REPO/commits/$sha/check-runs?per_page=100" 2>/dev/null); then
          echo "graphide-autoupdate: gh check-runs lookup failed, will retry next cycle"
          exit 0
        fi
        verdict=$(printf '%s' "$checks" | jq -r --arg wf "$WORKFLOW" '
          [.check_runs[] | select(.app.slug == "depot-code-access" and (.name | startswith($wf + " / ")))]
          | if length == 0 then "none"
            elif all(.conclusion == "success") then "success"
            else "other" end')
        if [ "$verdict" = "success" ]; then
          green=$sha
          break
        fi
      done
      if [ -z "$green" ]; then
        echo "graphide-autoupdate: no commit in master's last 40 has a fully green '$WORKFLOW', skipping"
        exit 0
      fi

      gred_built=""
      [ -f "$GRED_REV_MARKER" ] && gred_built=$(cat "$GRED_REV_MARKER")

      # Tracked separately from flake.lock's pin on purpose: the marker only
      # advances on a *successful* gred build (see below), while the re-pin
      # a few lines down happens unconditionally once gr/grat's build is
      # done. Comparing "already up to date" against $current alone would
      # mean a single failed gred build (e.g. the transient apt-get network
      # blip this hit once) got silently locked in forever -- $current would
      # already equal $green on every later run, so this check would keep
      # exiting early and gred would never get retried until master moved
      # again.
      if [ "$green" = "$current" ] && [ "$green" = "$gred_built" ] && [ "$green" = "$gred_current" ]; then
        echo "graphide-autoupdate: already up to date at $current"
        exit 0
      fi

      need_switch=0

      if [ "$green" = "$gred_built" ]; then
        echo "graphide-autoupdate: gred already built from $green, skipping"
      else
        # Rebuild gred from $green in a dedicated clean clone -- NOT the
        # interactive checkout under Documents/startup/Graphide/monolith,
        # which is a live working tree that can hold uncommitted edits an
        # unattended `git checkout $green` would discard. graphide-rebuild-
        # gred already does the actual build (Docker, reusing the layer
        # cache and the npm/build cache under ~/.cache/graphide), so this
        # just keeps that clone in sync with $green and hands it off.
        #
        # A failure here does not call fail(): it would abort the gr/grat
        # re-pin below over a problem that is purely gred's. Worst case,
        # gred stays on its previous build and $GRED_REV_MARKER is left
        # untouched, so the check above retries it next cycle instead of
        # accepting the failure as final.
        echo "graphide-autoupdate: syncing gred build clone to $green ..."
        if [ ! -d "$GRED_SRC_DIR/.git" ]; then
          mkdir -p "$(dirname "$GRED_SRC_DIR")"
          git clone --quiet "$CLONE_URL" "$GRED_SRC_DIR" || true
        fi
        # Discard whatever the last build left behind BEFORE checking out.
        # gred commits its own compiled artifacts under
        # gred/extensions/graphide/out, so every build writes over tracked
        # files and also drops new untracked ones. The moment master starts
        # tracking a file the previous build had only generated locally,
        # `git checkout` refuses -- "untracked working tree files would be
        # overwritten" -- and since nothing ever cleaned this clone, that is
        # not a transient failure: it wedges gred on its last good build and
        # every later cycle hits the identical wall. That is exactly what
        # happened on 2026-09-13, when 34 generated out/webview/*.js files
        # became tracked and froze the editor 104 commits behind master
        # while gr/grat kept advancing normally.
        #
        # -ffd, deliberately NOT -ffdx: the ignored paths here are
        # node_modules and gred/dist, i.e. the npm and build caches this
        # whole clone exists to reuse. Clearing those would turn every
        # cycle into a from-scratch install.
        if [ -d "$GRED_SRC_DIR/.git" ] \
            && git -C "$GRED_SRC_DIR" fetch --quiet origin "$green" \
            && git -C "$GRED_SRC_DIR" reset --quiet --hard \
            && git -C "$GRED_SRC_DIR" clean -qffd \
            && git -C "$GRED_SRC_DIR" checkout --quiet --detach FETCH_HEAD; then
          if graphide-rebuild-gred "$GRED_SRC_DIR"; then
            echo "$green" > "$GRED_REV_MARKER"
            need_switch=1
            echo "graphide-autoupdate: gred rebuilt from $green"
          else
            echo "graphide-autoupdate: gred rebuild failed at $green, leaving gred on its previous build" >&2
            notify-send -u normal "Graphide gred build failed" \
              "gred stays on its previous build; will retry next cycle" || true
          fi
        else
          echo "graphide-autoupdate: could not sync gred clone to $green, leaving gred on its previous build" >&2
          notify-send -u normal "Graphide gred build skipped" \
            "could not sync the build clone; will retry next cycle" || true
        fi
      fi

      # gred's pin follows the tarball that actually exists, never $green
      # directly: the derivation checks the tarball against the tree it is
      # evaluated in, so pinning ahead of a build is exactly the failure this
      # split exists to prevent.
      if [ -n "$gred_built" ] && [ "$gred_built" != "$gred_current" ]; then
        echo "graphide-autoupdate: re-pinning graphide-gred $gred_current -> $gred_built"
        if ! nix flake lock --override-input graphide-gred "$GIT_URL?rev=$gred_built"; then
          fail "could not re-pin graphide-gred to $gred_built"
        fi
        need_switch=1
      fi

      if [ "$green" = "$current" ]; then
        echo "graphide-autoupdate: gr/grat already at $current"
      else
        echo "graphide-autoupdate: re-pinning graphide $current -> $green"
        # Local only, on purpose: this rewrites flake.lock in the working
        # tree and never commits or pushes it. The lock in git stays
        # whatever a human put there; `git checkout flake.lock` is the whole
        # undo. No --refresh here or on the switch below -- nix re-reads a
        # dirty worktree on every evaluation, so the switch already sees
        # the flake.lock this call just wrote.
        if ! nix flake lock --override-input graphide "$GIT_URL?rev=$green"; then
          fail "could not re-pin flake.lock to $green"
        fi
        need_switch=1
      fi

      if [ "$need_switch" = 1 ]; then
        # home-manager switch builds before it activates, so a broken
        # commit leaves the current generation running and just fails this
        # unit. That is the correct outcome -- do not wrap it in a rollback.
        if ! home-manager switch --flake "$FLAKE_DIR#$FLAKE_ATTR" --impure; then
          fail "home-manager switch failed on graphide $green"
        fi
        echo "graphide-autoupdate: switched to graphide $green"
      else
        echo "graphide-autoupdate: nothing to switch"
      fi
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
          a user timer that re-pins the graphide flake input to the newest
          green master commit and switches home-manager onto it. Separate
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

        workflow = lib.mkOption {
          type = lib.types.str;
          default = "push gate";
          description = ''
            The GitHub Actions workflow that defines "green" -- the check
            that actually gates merges to master.
          '';
        };

        gredBuildDir = lib.mkOption {
          type = lib.types.str;
          default = "${config.home.homeDirectory}/.cache/graphide/gred-autobuild-src";
          description = ''
            Dedicated clean clone the timer builds gred from, kept in sync
            with the newest green master commit. Deliberately separate from
            the interactive checkout under
            Documents/startup/Graphide/monolith -- that one is a live working
            tree that can hold uncommitted edits, and an unattended
            `git checkout` there on every timer tick would discard them.
          '';
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
        rebuildGredScript
        # On PATH unconditionally (not gated on autoUpdate.enable) so the
        # 30m timer can stay off and this becomes the manual "update now"
        # command instead. Reads the same cfg.autoUpdate.* options
        # (flakeDir/workflow/gredBuildDir) for its defaults either way.
        autoUpdateScript
      ];
    }

    (lib.mkIf cfg.autoUpdate.enable {
      systemd.user.services.graphide-autoupdate = {
        Unit = {
          Description = "Rebuild gred and re-pin gr/grat to the newest green graphide master commit, then switch";
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
          # on a machine running several agents plus a 12-CPU Docker build it
          # can be starved indefinitely, and nix evaluation is almost pure
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
          # Default TimeoutStartSec (90s) would kill this mid-build: the gred
          # rebuild is a real Docker build, not just a nix re-pin. Same value
          # as the analogous timer-triggered builds in
          # system/graphide/{web,demo}.nix.
          # The container guard in graphide-rebuild-gred is what stops a
          # timed-out build from living on, not this number.
          TimeoutStartSec = "2h";
        };
      };

      systemd.user.timers.graphide-autoupdate = {
        Unit.Description = "Check for a newer green graphide master commit";
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
