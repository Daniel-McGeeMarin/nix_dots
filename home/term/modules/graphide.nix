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
  gred = gp.gred.overrideAttrs (_: { src = gredDistTarball; });

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

      WORK="$(mktemp -d)"
      trap 'rm -rf "$WORK"' EXIT

      echo "[1/3] Building Go binaries (grug, gr, grach) + bwrap in a stock-glibc container ..."
      bash "$MONOLITH_DIR/scripts/build-dist-container.sh" linux amd64 "$WORK/bins"

      echo "[2/3] Building the release image and tarball (this reuses the npm/build cache under ~/.cache/graphide) ..."
      docker build -t graphide-build-env -f "$MONOLITH_DIR/gred/build/Dockerfile" "$MONOLITH_DIR/gred"
      mkdir -p "$HOME/.cache/graphide"
      docker run --rm -u "$(id -u):$(id -g)" \
        -v "$HOME/.cache/graphide":"$HOME/.cache/graphide" \
        -v "$MONOLITH_DIR":"$MONOLITH_DIR" \
        -v "$WORK/bins":"$WORK/bins" \
        -e HOME=/tmp \
        -e MONOREPO_DIR="$MONOLITH_DIR" \
        -e GRAPHIDE_GO_BIN_DIR="$WORK/bins" \
        graphide-build-env bash "$MONOLITH_DIR/gred/build/build-release.sh" linux-x64

      echo "[3/3] Installing the tarball ..."
      mkdir -p "$HOME/MyApps/graphide-dist"
      cp "$MONOLITH_DIR/gred/dist/graphide-linux-x64.tar.gz" "$HOME/MyApps/graphide-dist/graphide-linux-x64.tar.gz"

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
      if [ "$green" = "$current" ] && [ "$green" = "$gred_built" ]; then
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
        if [ -d "$GRED_SRC_DIR/.git" ] \
            && git -C "$GRED_SRC_DIR" fetch --quiet origin "$green" \
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
      ];
    }

    (lib.mkIf cfg.autoUpdate.enable {
      systemd.user.services.graphide-autoupdate = {
        Unit = {
          Description = "Rebuild gred and re-pin gr/grat to the newest green graphide master commit, then switch";
          After = [ "network-online.target" ];
          Wants = [ "network-online.target" ];
        };
        # Unlike a NixOS system unit, home-manager never auto-restarts a
        # running service whose definition changed -- systemd-activate.sh
        # only prints a "Suggested commands: systemctl --user restart ..."
        # after `switch`, it doesn't run it. So a `homeswitch` while this is
        # mid-build (this file gets edited a lot) can't get stuck stopping
        # it; no restartIfChanged/stopIfChanged equivalent needed here.
        Service = {
          Type = "oneshot";
          ExecStart = lib.getExe autoUpdateScript;
          # A nix build should never win a scheduling fight with the editor
          # it's about to replace.
          Nice = 10;
          IOSchedulingClass = "idle";
          # Default TimeoutStartSec (90s) would kill this mid-build: the gred
          # rebuild is a real Docker build, not just a nix re-pin. Same value
          # as the analogous timer-triggered builds in
          # system/graphide/{web,demo}.nix.
          TimeoutStartSec = "60min";
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
