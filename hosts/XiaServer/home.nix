{ config, lib, pkgs, inputs, ... }:

# XiaServer is headless. It imports only the terminal half of home/ - the shell,
# the editor and the dev tooling you want when you SSH in. The graphical half
# (home/desktop: Hyprland, caelestia, browsers, Flatpak apps) is simply not in
# the module set, so there is nothing to switch off and nothing that can leak
# back in by forgetting a guard.
{
  imports = [
    ../../home/term
  ];

  programs.home-manager.enable = true;
  home.username = "XiaServer";
  home.homeDirectory = "/home/XiaServer";

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
