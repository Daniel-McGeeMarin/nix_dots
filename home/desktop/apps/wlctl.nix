{ pkgs, lib, ... }:
# wlctl -- the Wi-Fi manager (SUPER+N, and the Graphide bar's Wi-Fi item).
#
# A terminal UI for NetworkManager: a fork of impala (the well-liked iwd TUI)
# pointed at NM instead, so it sees the same saved networks as nmcli and both
# shells. Known and nearby networks side by side, live signal, Enter to join,
# a password box inline, `d` to forget, `t` for auto-connect, `v` for VPN
# profiles, and `wlctl doctor` to find which layer is broken when the
# internet is not. It replaced the rofi Wi-Fi tab, which needed a second
# rofi for every password prompt and could not show anything live.
#
# Not in nixpkgs, so built here from the tagged release. To move to a newer
# one, bump `version` and replace `hash` with what
# `nix flake prefetch github:aashish-thapa/wlctl/v<version>` prints.
#
# Changing Wi-Fi without sudo is not this file: see the `networkmanager`
# group in ../../../hosts/XiaNix/configuration.nix.
let
  wlctl = pkgs.rustPlatform.buildRustPackage rec {
    pname = "wlctl";
    version = "0.1.10";
    src = pkgs.fetchFromGitHub {
      owner = "aashish-thapa";
      repo = "wlctl";
      rev = "v${version}";
      hash = "sha256-ecjh4pYRLb0Ic/gWmfvEakzeQXhTfBe+zCFtqCsGeKw=";
    };
    # Upstream's own lockfile, so there is no vendor hash to keep in step.
    cargoLock.lockFile = "${src}/Cargo.lock";
    meta = {
      description = "Wi-Fi TUI for NetworkManager";
      homepage = "https://github.com/aashish-thapa/wlctl";
      license = lib.licenses.gpl3Only;
      mainProgram = "wlctl";
      platforms = lib.platforms.linux;
    };
  };

  # SUPER+N toggles it: closes the window if one is open, otherwise opens it
  # in a kitty the `wlctl` window rules in ../env/hyprland/rules.nix float and
  # centre.
  wifi = pkgs.writeShellApplication {
    name = "wifi";
    runtimeInputs = [ wlctl pkgs.kitty pkgs.jq pkgs.hyprland ];
    text = ''
      if hyprctl clients -j | jq -e 'any(.[]; .class == "wlctl")' >/dev/null; then
        exec hyprctl dispatch closewindow 'class:^(wlctl)$'
      fi
      exec kitty --class wlctl --title Wi-Fi -e wlctl
    '';
  };
in
{
  home.packages = [ wlctl wifi ];
}
