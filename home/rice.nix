{ pkgs, lib, config, ... }:
# Theming glue: Qt platform theme, cursor theme, and the Flatpak overrides that
# let sandboxed apps see the host's GTK themes and fonts.
#
# All of it is gated on desktop.enable. The flatpak override and the cursor
# package used to sit outside the guard, which meant a headless host still
# activated the Flatpak module and carried a cursor theme it can never draw.
{
  config = lib.mkIf config.desktop.enable {
    home.sessionVariables = {
      QT_QPA_PLATFORM = "wayland";
    };
    qt = {
      enable = true;
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
  };
}
