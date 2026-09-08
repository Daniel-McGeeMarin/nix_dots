{ pkgs, lib, ... }:
let
  hyprWorkspaceCycle = pkgs.writeShellScriptBin "hypr-workspace-cycle" (builtins.readFile ./hypr-workspace-cycle.sh);
  hyprWorkspaceNext = pkgs.writeShellScriptBin "hypr-workspace-next" ''exec "${hyprWorkspaceCycle}/bin/hypr-workspace-cycle" next'';
  hyprWorkspacePrev = pkgs.writeShellScriptBin "hypr-workspace-prev" ''exec "${hyprWorkspaceCycle}/bin/hypr-workspace-cycle" prev'';
in
{
  wayland.windowManager.hyprland.settings = {

    ### Monitors and devices ###
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

      # Background buffer terms so they don't block the rotation logic
      "kitty --class BufferTerm1 -e sleep infinity &"
      "kitty --class BufferTerm2 -e sleep infinity &"
      "kitty --class BufferTerm3 -e sleep infinity &"

      "${pkgs.kdePackages.kdeconnect-kde}/bin/kdeconnect-indicator &"

      "sleep 4"
      "[workspace 22 silent; fullscreen] flatpak run com.github.xournalpp.xournalpp"
      "firefox"

      "${hyprWorkspaceCycle}/bin/hypr-workspace-cycle rotation-vertical"
      "waydroid show-full-ui &"
      "flatpak run com.github.xournalpp.xournalpp &"
      "sleep 12 && ${hyprWorkspaceCycle}/bin/hypr-workspace-cycle rotation-landscape &"
    ];

    ### Input hardware ###
    input = {
      kb_layout = "us";
      kb_options = "caps:swapescape";
      follow_mouse = 1;
      accel_profile = "flat";
      force_no_accel = 1;
      sensitivity = 0.8;
      scroll_factor = 0.6;
      touchpad = {
        natural_scroll = true;
        disable_while_typing = false;
        drag_lock = 2;
        scroll_factor = 0.5;
      };
    };

    cursor.no_hardware_cursors = 1;

    ### Appearance ###
    general = {
      gaps_in = 6;
      gaps_out = 10;
      border_size = 2;
      "col.active_border" = "rgba(e6e6e6cc) rgba(d0d0d0aa) 45deg";
      "col.inactive_border" = "rgba(595959aa)";
      layout = "master";
      allow_tearing = false;
    };

    decoration = {
      rounding = 10;
      blur = {
        enabled = true;
        size = 3;
        passes = 2;
        new_optimizations = true;
        noise = 0.02;
      };
      shadow = {
        enabled = true;
        range = 4;
        render_power = 3;
        color = "rgba(1a1a1aee)";
      };
    };

    animations = {
      enabled = lib.mkDefault true;
      bezier = "myBezier,0.05,0.9,0.1,1.05";
      animation = [
        "windows,1,7,myBezier"
        "windowsOut,1,7,default,popin 80%"
        "border,1,10,default"
        "borderangle,1,8,default"
        "fade,1,7,default"
        "workspaces,1,6,default"
      ];
    };

    ### Layout ###
    master.new_on_top = false;
    dwindle = {
      pseudotile = true;
      preserve_split = true;
    };

    misc = {
      force_default_wallpaper = -1;
      enable_swallow = false;
      swallow_regex = "^(Alacritty|kitty|footclient|foot)$";
    };

    debug.disable_scale_checks = true;
    xwayland.force_zero_scaling = true;
  };
}
