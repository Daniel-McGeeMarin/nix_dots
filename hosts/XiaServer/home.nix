{ config, lib, pkgs, inputs, ... }:

# XiaServer is headless. Everything here is what you want when you SSH in to
# administer the box - a shell, an editor, git tooling - and nothing that draws
# pixels. desktop.enable is the switch that keeps the whole home/desktop tree
# (Hyprland, caelestia, browsers, Flatpak apps) out of this profile.
{
  imports = [
    ../../home
  ];

  programs.home-manager.enable = true;
  home.username = "XiaServer";
  home.homeDirectory = "/home/XiaServer";

  desktop.enable = false;

  # Kept on: the box clones and builds repos (see the autoBuild units in
  # system/serv/), and this is what makes poking at those checkouts bearable.
  programming.enable = true;

  ai.enable = false;
  ai.claudeCode.enable = true;

  # No display, no speakers, no MPD - see the comment in home/term/default.nix.
  media.enable = false;

  home.packages = with pkgs; [
    nix-output-monitor
  ];

  home.stateVersion = "24.11";
}
