# Overlay patches applied to caelestia-shell before it builds.
# Patches are unified diffs against the caelestia-shell source tree.
#
# To add a patch:
#   1. Generate: diff -u original.qml modified.qml > home-manager/desktop/env/caelestia/patches/my-feature.patch
#   2. Add it to the list below.
#
# To remove when upstream merges a fix:
#   1. Delete the .patch file.
#   2. Remove it from the list below.
#
# Usage in home.nix:
#   package = import ../../home-manager/desktop/env/caelestia/patches {
#     caelestia-shell = inputs.caelestia-shell.packages.${pkgs.stdenv.hostPlatform.system}.with-cli;
#   };
#
# IMPORTANT: pass with-cli directly — do NOT call .override { withCli = true; }
# after this, as override() recreates the derivation from callPackage args and
# silently drops all overrideAttrs patches.

{ caelestia-shell }:
caelestia-shell.overrideAttrs (old: {
  patches = (old.patches or []) ++ [
    ./workspace-icons.patch
  ];
})
