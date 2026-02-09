{ lib, pkgs, config, ... }:

{
  services.hyprpaper = {
    enable = true;
    settings = {
      preload = [ "${config.home.homeDirectory}/Pictures/Wallpapers/e7.jpg" ];
      wallpaper = [
        "eDP-1,${config.home.homeDirectory}/Pictures/Wallpapers/e7.jpg"
        "DP-5,${config.home.homeDirectory}/Pictures/Wallpapers/e7.jpg"
      ];
    };
  };

  wayland.windowManager.hyprland.settings.exec-once =
    lib.mkIf config.services.hyprpaper.enable [
      "systemctl --user restart hyprpaper.service"
    ];

}

