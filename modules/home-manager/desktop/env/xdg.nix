{ pkgs, config, lib, osConfig, ... }:
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
          (lib.mkIf osConfig.services.xserver.desktopManager.gnome.enable gnome-session)
        ];
        extraPortals = with pkgs; [
          (lib.mkIf osConfig.services.xserver.desktopManager.gnome.enable xdg-desktop-portal-gtk)
          (lib.mkIf osConfig.programs.hyprland.enable xdg-desktop-portal-hyprland)
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
