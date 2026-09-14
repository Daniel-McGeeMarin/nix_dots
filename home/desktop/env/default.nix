{ config, lib, pkgs, osConfig, ... }:
let
  gnomeEnabled = ((osConfig.services or { }).desktopManager or { }).gnome.enable or false;
in
{
  imports = [
    # Two desktop shells and the runtime switch between them. ./shells.nix
    # declares `desktop.shell`, installs the `rice` command and owns the one
    # unit that starts a shell at login; the two directories are the shells.
    ./shells.nix
    ./caelestia
    ./graphide-shell
    ./claude-agents.nix
    ./gnome
    ./hyprland
    ./rofi
  ];

  config = {
    systemd.user.settings.Manager.DefaultEnvironment = {
      PATH = "/run/wrappers/bin:/etc/profiles/per-user/%u/bin:/nix/var/nix/profiles/default/bin:/run/current-system/sw/bin";
    };
    xdg = {
      enable = true;
      portal = {
        enable = true;
        xdgOpenUsePortal = true;
        configPackages = with pkgs; lib.optionals gnomeEnabled [ gnome-session ];
        extraPortals = with pkgs; lib.optionals gnomeEnabled [ xdg-desktop-portal-gtk ]
          ++ lib.optionals ((osConfig.programs or { }).hyprland.enable or false) [ xdg-desktop-portal-hyprland ];
      };
      mime.enable = true;
      mimeApps.enable = true;
      userDirs = {
        enable = true;
        createDirectories = true;
      };
    };
  };
}
