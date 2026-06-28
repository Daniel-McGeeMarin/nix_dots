{ pkgs, lib, config, ... }:
{
  home.sessionVariables = lib.mkIf config.desktop.enable {
    QT_QPA_PLATFORM = "wayland";
  };
  qt = {
    enable = lib.mkIf config.desktop.enable true;
    platformTheme.name = "qt5ct";
  };
  services.flatpak.overrides.global = {
    Context.filesystems = [
      "xdg-config/gtk-4.0:ro"
      "xdg-config/gtk-3.0:ro"
      "xdg-config/themes/:ro"
      "/run/current-system/sw/share/X11/fonts:ro"
      "/nix/store:ro"
      "xdg-data/fonts/:ro"
    ];
    Environment = {
      XCURSOR_PATH = "/run/host/user-share/icons:/run/host/share/icons";
    };
  };
  home.pointerCursor = {
    package = pkgs.graphite-cursors;
    gtk.enable = false;
    name = "graphite-dark";
  };
}
