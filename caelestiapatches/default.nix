# Overlay patches applied to caelestia-shell before it builds.
# Patches are unified diffs against the caelestia-shell source tree.
#
# To add a patch:
#   1. Generate: diff -u original.qml modified.qml > caelestiapatches/my-feature.patch
#   2. Add it to the list below.
#
# To remove when upstream merges a fix:
#   1. Delete the .patch file.
#   2. Remove it from the list below.
#
# Usage in home.nix:
#   package = (import ../../caelestiapatches {
#     caelestia-shell = inputs.caelestia-shell.packages.${pkgs.stdenv.hostPlatform.system}.caelestia-shell;
#   }).override { withCli = true; };

{ caelestia-shell }:
caelestia-shell.overrideAttrs (old: {
  patches = (old.patches or []) ++ [
    ./workspace-icons.patch
  ];
})
