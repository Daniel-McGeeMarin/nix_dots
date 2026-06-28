{ ... }:
{
  wayland.windowManager.hyprland.settings = {
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

    dwindle = {
      pseudotile = true;
      preserve_split = true;
    };
  };
}
