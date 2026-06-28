{ pkgs, ... }:
let
  hyprWorkspaceCycle = pkgs.writeShellScriptBin "hypr-workspace-cycle" (builtins.readFile ./hypr-workspace-cycle.sh);
  hyprWorkspaceNext = pkgs.writeShellScriptBin "hypr-workspace-next" ''exec "${hyprWorkspaceCycle}/bin/hypr-workspace-cycle" next'';
  hyprWorkspacePrev = pkgs.writeShellScriptBin "hypr-workspace-prev" ''exec "${hyprWorkspaceCycle}/bin/hypr-workspace-cycle" prev'';
in
{
  wayland.windowManager.hyprland.settings = {
    # eDP-1 = built-in display; DP-5 = external
    monitor = [
      "eDP-1,preferred,auto,1.5"
      "DP-5,preferred,auto,1.5"
    ];

    device = [
      { name = "elan-touchscreen"; output = "eDP-1"; }
      { name = "elan-touchscreen-stylus"; output = "eDP-1"; }
    ];

    exec-once = [
      "systemctl --user restart xdg-desktop-portal.service"
      "nmcli radio wifi off && nmcli radio wifi on &"
      "bwfloat &"
      "nm-applet &"
      "squeekboard &"
      "signal-desktop &"
      "kitty --class StartupTerm &"

      # Background buffer terms so they don't block rotation logic
      "kitty --class BufferTerm1 -e sleep infinity &"
      "kitty --class BufferTerm2 -e sleep infinity &"
      "kitty --class BufferTerm3 -e sleep infinity &"

      "${pkgs.kdePackages.kdeconnect-kde}/bin/kdeconnect-indicator &"

      "sleep 4"
      "[workspace 22 silent; fullscreen] flatpak run com.github.xournalpp.xournalpp"
      "zen"

      "${hyprWorkspaceCycle}/bin/hypr-workspace-cycle rotation-vertical"
      "waydroid show-full-ui &"
      "flatpak run com.github.xournalpp.xournalpp &"
      "sleep 12 && ${hyprWorkspaceCycle}/bin/hypr-workspace-cycle rotation-landscape &"
    ];

    master.new_on_top = false;
  };
}
