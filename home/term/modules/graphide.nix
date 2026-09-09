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
  # Consequence worth knowing: this ties gred to whatever commit
  # graphide-rebuild-gred was last run against. graphide.autoUpdate re-pins
  # gr/grat to the newest green master commit on its own, but gred stays on
  # this exact build until graphide-rebuild-gred is run again by hand --
  # there is no CI artifact for the timer to fetch instead. Run it after
  # pulling meaningful gred changes; there's no way to automate that without
  # graphide publishing real releases.
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
    ];
    text = ''
      FLAKE_DIR=${lib.escapeShellArg cfg.autoUpdate.flakeDir}
      FLAKE_ATTR=${lib.escapeShellArg flakeAttr}
      REPO=${lib.escapeShellArg graphideRepo}
      WORKFLOW=${lib.escapeShellArg cfg.autoUpdate.workflow}
      GIT_URL=${lib.escapeShellArg graphideGitURL}

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
      # NOT `gh run list --workflow "push gate"`. That resolves the name
      # against the repo's workflow *listing*; asking for every recent master
      # run and picking the workflow out in jq is version-independent, and one
      # request either way.
      if ! runs=$(gh run list --repo "$REPO" --branch master \
            --json workflowName,headSha,conclusion,createdAt --limit 60 2>&1); then
        echo "graphide-autoupdate: gh lookup failed, will retry next cycle: $runs"
        exit 0
      fi

      green=$(printf '%s' "$runs" \
        | jq -r --arg wf "$WORKFLOW" \
            'map(select(.workflowName == $wf and .conclusion == "success"))
             | sort_by(.createdAt) | reverse | .[0].headSha // empty' 2>/dev/null || true)
      if [ -z "$green" ]; then
        echo "graphide-autoupdate: no successful '$WORKFLOW' run on master in the last 60, skipping"
        exit 0
      fi

      if [ "$green" = "$current" ]; then
        echo "graphide-autoupdate: already up to date at $current"
        exit 0
      fi

      echo "graphide-autoupdate: re-pinning graphide $current -> $green"
      # Local only, on purpose: this rewrites flake.lock in the working tree
      # and never commits or pushes it. The lock in git stays whatever a
      # human put there; `git checkout flake.lock` is the whole undo.
      # No --refresh here or on the switch below -- nix re-reads a dirty
      # worktree on every evaluation, so the switch already sees the
      # flake.lock this call just wrote.
      if ! nix flake lock --override-input graphide "$GIT_URL?rev=$green"; then
        fail "could not re-pin flake.lock to $green"
      fi

      # home-manager switch builds before it activates, so a broken commit
      # leaves the current generation running and just fails this unit. That
      # is the correct outcome -- do not wrap it in a rollback.
      if ! home-manager switch --flake "$FLAKE_DIR#$FLAKE_ATTR"; then
        fail "home-manager switch failed on graphide $green"
      fi

      echo "graphide-autoupdate: switched to graphide $green"
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
          Description = "Re-pin the graphide flake input to the newest green master commit and switch";
          After = [ "network-online.target" ];
          Wants = [ "network-online.target" ];
        };
        Service = {
          Type = "oneshot";
          ExecStart = lib.getExe autoUpdateScript;
          # A nix build should never win a scheduling fight with the editor
          # it's about to replace.
          Nice = 10;
          IOSchedulingClass = "idle";
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
