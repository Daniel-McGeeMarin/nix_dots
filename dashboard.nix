# `nix run .#dashboard` -- put the hackerboard on the screen.
#
# The board itself lives in the Graphide monorepo (`monolith/hackerboard/`),
# not here: it is an application, and this repo is machine configuration. What
# lives here is the entry point, so the command works from anywhere inside
# ~/nixos without having to remember where the monorepo is checked out.
#
# It deliberately does *not* add the monorepo as a flake input. That would drag
# monolith's whole input set (including a pinned VS Code source tree) into this
# flake's lock file, and would mean re-pinning the lock every time the board
# changes. Shelling out keeps this repo's lock untouched and always runs the
# board as it currently is in the checkout.
{ pkgs }:

pkgs.writeShellApplication {
  name = "dashboard";
  runtimeInputs = [ pkgs.git ];
  text = ''
    MONOLITH="''${GRAPHIDE_MONOLITH:-$HOME/Documents/startup/Graphide/monolith}"

    if [ ! -f "$MONOLITH/flake.nix" ]; then
      echo "dashboard: no Graphide monorepo at $MONOLITH" >&2
      echo "           set GRAPHIDE_MONOLITH to the checkout, e.g." >&2
      echo "           GRAPHIDE_MONOLITH=~/src/monolith nix run ~/nixos#dashboard" >&2
      exit 1
    fi

    # A flake only sees git-tracked files. A brand new file in the board that
    # has never been staged is invisible to the build, and the failure reads as
    # "that file does not exist" -- which is baffling if you are looking at it.
    if [ -n "$(git -C "$MONOLITH" ls-files --others --exclude-standard -- hackerboard 2>/dev/null)" ]; then
      echo "dashboard: note -- hackerboard has untracked files; nix will not see them." >&2
      echo "           git -C $MONOLITH add hackerboard" >&2
    fi

    exec nix run "git+file://$MONOLITH#hackerboard" -- "$@"
  '';
}
