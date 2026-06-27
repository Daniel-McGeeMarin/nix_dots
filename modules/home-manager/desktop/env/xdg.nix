{ pkgs, config, lib, osConfig, ... }:

let
  gnomeEnabled =
    ((osConfig.services or { }).xserver or { }).enable or false
    && ((osConfig.services.xserver or { }).desktopManager or { }).gnome.enable or false;
in
{
  config = lib.mkIf config.desktop.enable {
    systemd.user.settings.Manager.DefaultEnvironment = {
      PATH = "/run/wrappers/bin:/etc/profiles/per-user/%u/bin:/nix/var/nix/profiles/default/bin:/run/current-system/sw/bin";
    };
    xdg = {
      enable = true;
      portal = {
        enable = true;
        xdgOpenUsePortal = true;
        configPackages = with pkgs; [
          (lib.mkIf gnomeEnabled gnome-session)
        ];
        extraPortals = with pkgs; [
          (lib.mkIf gnomeEnabled xdg-desktop-portal-gtk)
          (lib.mkIf ((osConfig.programs or { }).hyprland.enable or false) xdg-desktop-portal-hyprland)
        ];
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
