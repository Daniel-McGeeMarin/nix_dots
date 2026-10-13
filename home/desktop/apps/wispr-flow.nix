{ config, lib, pkgs, inputs, ... }:
# Wispr Flow -- voice dictation (github:wispr-flow-linux/wispr-flow-linux).
# Wispr ships only macOS and Windows builds; this unofficial port repackages
# the Windows installer's Electron app and adds a clean-room Rust helper that
# types the transcript into the focused window. Sign in with the normal Wispr
# account inside the app.
#
# The port's derivation never downloads the proprietary installer itself, so
# it is fetched here, from Wispr's own CDN, by the URL and SHA-256 in the
# port's scripts/setup/installer-pin.sh. Reading the pin out of the same input
# keeps the installer and the derivation's patches in step: bump with
#   nix flake update wispr-flow
#
# Permissions it needs are already on for XiaNix, no extra system config:
#   /dev/uinput writable (text injection)  -- hardware.uinput.enable via head.gaming
#   /dev/input/event* readable (push-to-talk) -- xia is in the `input` group
#   wl-clipboard (paste on Wayland)        -- home/desktop/default.nix
# `wispr-flow --doctor` checks all of them.
let
  src = inputs.wispr-flow;
  system = pkgs.stdenv.hostPlatform.system;

  pin = builtins.readFile "${src}/scripts/setup/installer-pin.sh";
  pinned = name: builtins.head (builtins.match ".*\n${name}='([^']*)'.*" pin);

  installer = pkgs.fetchurl {
    name = "wispr-flow-setup-${pinned "WISPR_VERSION"}.exe";
    url = pinned "WISPR_INSTALLER_URL";
    sha256 = pinned "WISPR_INSTALLER_SHA256";
  };

  wispr-flow = src.packages.${system}.wispr-flow.override { installerExe = installer; };

  # The glibc FHS wrapper is the port's recommended output on NixOS (Electron
  # wants /lib64/ld-linux). pkgs.unfree because it inherits the app's unfree meta.
  wispr-flow-fhs = pkgs.unfree.callPackage "${src}/nix/fhs.nix" { inherit wispr-flow; };
in
{
  home.packages = [ wispr-flow-fhs ];
}
