{ pkgs, lib, config, ... }:
# Theming glue: the Qt platform theme, the cursor theme, and the Flatpak
# overrides that let sandboxed apps see the host's GTK themes and fonts.
#
# No guard: this file is part of home/desktop, and a host that does not import
# that tree never sees it. It used to live at home/rice.nix, outside the tree,
# where two of the four blocks below were applied to every host including the
# headless one.
{
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
}
