# `dashboard` -- put the hackerboard on the screen.
#
# The board itself lives in the Graphide monorepo (`monolith/hackerboard/`),
# not here: it is an application, and this repo is machine configuration. What
# lives here is the entry point.
#
# It deliberately does *not* add the monorepo as a flake input. That would drag
# monolith's whole input set (including a pinned VS Code source tree) into this
# flake's lock file, and would mean re-pinning the lock every time the board
# changes. Shelling out keeps this repo's lock untouched and always runs the
# board as it currently is in the checkout.
#
# `defaultSrc` is where the checkout is on *this machine*, baked in at build
# time. It matters that the caller supplies it: the first version of this file
# defaulted to a path under $HOME, which is right on a laptop and wrong on the
# server, where the checkout is the one the demo autobuild maintains under
# /srv. GRAPHIDE_MONOLITH still overrides, but nothing has to set it.
{ pkgs, defaultSrc ? null }:

pkgs.writeShellApplication {
  name = "dashboard";
  # nix is explicit rather than ambient: tv-run launches this as a systemd
  # --user unit, which has no shell profile to put nix on PATH.
  runtimeInputs = [ pkgs.nix pkgs.git ];
  text = ''
    BAKED=${if defaultSrc == null then ''"$HOME/Documents/startup/Graphide/monolith"'' else ''"${defaultSrc}"''}
    MONOLITH="''${GRAPHIDE_MONOLITH:-$BAKED}"

    # On a wall display, exiting with a message on stderr is the same thing as
    # exiting silently -- nobody is reading the journal, and the screen keeps
    # whatever was there before. Put the reason where the failure is visible.
    fail() {
      echo "dashboard: $*" >&2
      if [ -n "''${WAYLAND_DISPLAY:-}''${DISPLAY:-}" ] && command -v foot >/dev/null 2>&1; then
        msg="$(mktemp)"
        { echo "hackerboard failed to start"; echo; echo "$*"; } > "$msg"
        foot --title="hackerboard" sh -c "cat '$msg'; echo; echo 'press enter to close'; read -r _" \
          >/dev/null 2>&1 || true
        rm -f "$msg"
      fi
      exit 1
    }

    if [ ! -f "$MONOLITH/flake.nix" ]; then
      fail "no Graphide monorepo at $MONOLITH
    Set GRAPHIDE_MONOLITH to the checkout, or fix graphide.hackerboard.srcDir
    in the NixOS module that built this launcher."
    fi

    # A flake only sees git-tracked files. A brand new file in the board that
    # has never been staged is invisible to the build, and the failure reads as
    # "that file does not exist" -- which is baffling if you are looking at it.
    if [ -n "$(git -C "$MONOLITH" ls-files --others --exclude-standard -- hackerboard 2>/dev/null)" ]; then
      echo "dashboard: note -- hackerboard has untracked files; nix will not see them." >&2
      echo "           git -C $MONOLITH add hackerboard" >&2
    fi

    # First launch on a cold machine fetches chromium, a node toolchain and the
    # npm dependency set before anything can appear. Say so: several silent
    # minutes on a black screen is indistinguishable from broken.
    if ! nix path-info "git+file://$MONOLITH#hackerboard" >/dev/null 2>&1; then
      echo "dashboard: building the board (first run on this machine takes a few minutes)…" >&2
    fi

    if ! nix run "git+file://$MONOLITH#hackerboard" -- "$@"; then
      fail "the board exited with an error.
    Run \`dashboard --serve\` in a shell to see it, or:
    journalctl --user -u 'tv-dashboard-*' -e"
    fi
  '';
}
