{ lib, config, pkgs, inputs, osConfig, ... }:

{
  dconf = {
    enable = lib.mkIf osConfig.services.xserver.desktopManager.gnome.enable true;
    settings = {
      "org/gnome/desktop/interface".color-scheme = "prefer-dark";
      "org/gnome/shell".favorite-apps = [ "firefox.desktop" "foot.desktop" ];
      "org/gnome/desktop/wm/keybindings" = {
        activate-window-menu = "disabled";
        toggle-message-tray = "disabled";
        close = [ "<Super>q" ];
        maximize = "disabled";
        minimize = [ "<Super>comma" ];
        move-to-monitor-down = "disabled";
        move-to-monitor-left = "disabled";
        move-to-monitor-right = "disabled";
        move-to-monitor-up = "disabled";
        move-to-workspace-down = "disabled";
        move-to-workspace-up = "disabled";
        toggle-maximized = [ "<Super>f" ];
        move-to-workspace-1 = [ "<Super><Shift>1" ];
        move-to-workspace-2 = [ "<Super><Shift>2" ];
        move-to-workspace-3 = [ "<Super><Shift>3" ];
        move-to-workspace-4 = [ "<Super><Shift>4" ];
        switch-to-workspace-1 = [ "<Super>1" ];
        switch-to-workspace-2 = [ "<Super>2" ];
        switch-to-workspace-3 = [ "<Super>3" ];
        switch-to-workspace-4 = [ "<Super>4" ];
        unmaximize = "disabled";
      };
      "org/gnome/desktop/wm/preferences" = {
        num-workspaces = 10;
      };
    };
  };
}
