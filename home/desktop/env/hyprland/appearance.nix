{ lib, ... }:
{
  wayland.windowManager.hyprland.settings = {
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

    misc = {
      force_default_wallpaper = -1;
      enable_swallow = false;
      swallow_regex = "^(Alacritty|kitty|footclient|foot)$";
    };

    debug.disable_scale_checks = true;
    xwayland.force_zero_scaling = true;
  };
}
