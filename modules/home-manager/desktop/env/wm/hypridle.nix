{ config, pkgs, lib, ... }:

{
  home.packages = [
    pkgs.hypridle
  ];

  services.hypridle = {
    enable = true;
    settings = {
      general = {
        # Removed '--protocol layer-shell' and added '-f'
        lock_cmd = "pidof swaylock || swaylock -f";
        
        # Use the direct command here to bypass Caelestia
        before_sleep_cmd = "pidof swaylock || swaylock -f";
        
        after_sleep_cmd = "hyprctl dispatch dpms on";
      };

      # No activity for 10 minutes → lock and turn off display
      #if caelestia is on this is likeley ignored
      listener = [
        {
          timeout = 15;  # 10m
          on-timeout = "swaylock --protocol layer-shell";
          on-resume  = "hyprctl dispatch dpms on";
        }
      ];
    };
  };

  # swaylock-effects (mortie's fork) provides --submit-on-touch and blur/effects
  # https://github.com/mortie/swaylock-effects
  programs.swaylock = {
    enable = true;
    package = pkgs.swaylock-effects;
    settings = {
      # --- General ---
      screenshots = true;
      clock = true;
      indicator = true;
      indicator-radius = 140;      # Larger circle feels less "heavy"
      indicator-thickness = 6;     # Thinner ring looks more modern
      
      # --- Effects (Wallpaper stays bright) ---
      effect-blur = "7x5"; 
      #effect-vignette = "0.1:0.3"; # Lightened vignette to avoid "gloomy" corners

      # --- Font ---
      font = "sans-serif";
      timestr = "%H:%M";
      datestr = "%A, %B %e";
      font-size = 48;

      # --- The "Anti-Gloomy" Palette ---
      # 00000011 is only 6% black—just enough to let white text sit on it.
      "inside-color" = "00000070";      
      "ring-color" = "ffffff33";        # Faint white ring track
      
      # Text and Typing
      "text-color" = "ffffffff";        # Solid white text for clarity
      "key-hl-color" = "ffffffff";      # Solid white flash when typing
      "bs-hl-color" = "ffb3b3bb";       # Soft pink-white for backspace (less "angry" red)
      
      # States
      "ring-ver-color" = "ffffffff";    # Solid white for verifying
      "inside-ver-color" = "00000011";
      
      "ring-wrong-color" = "f38ba8ff";  # A softer pastel red for errors
      "inside-wrong-color" = "00000011";
      
      "ring-clear-color" = "ffffff33";  
      "inside-clear-color" = "00000011";

      # Clean edges
      "line-color" = "00000000";
      "separator-color" = "00000000";

      "submit-on-touch" = true;

    };
  };
}
