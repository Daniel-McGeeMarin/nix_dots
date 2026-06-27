{ pkgs, config, lib, ... }:

{
  config = lib.mkIf config.head.gram {

    security.sudo.extraRules = [
      {
        users = [ "xia" ];
        commands = [
          {
            command = "/run/current-system/sw/bin/waydroid shell wm size *";
            options = [ "NOPASSWD" ];
          }
          {
            command = "/run/current-system/sw/bin/waydroid shell wm density reset";
            options = [ "NOPASSWD" ];
          }
        ];
      }
    ];

    systemd.services.lg-gram-audio = {
      description = "LG Gram internal speaker amp init";
      wantedBy = [ "multi-user.target" ];
      after = [ "sound.target" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${pkgs.bash}/bin/bash ${./lg-gram-audio.sh}";
        RemainAfterExit = true;
      };
    };

    hardware.firmware = [ pkgs.sof-firmware ];

    environment.systemPackages = with pkgs; [
      alsa-tools
      input-remapper
      wvkbd
      squeekboard
      iio-hyprland
    ];

    hardware.sensor.iio.enable = true;

    services.input-remapper = {
      enable = true;
      enableUdevRules = true;
    };

    security.polkit.enable = true;

    i18n.inputMethod = {
      enable = true;
      type = "fcitx5";
      fcitx5.addons = with pkgs; [
        fcitx5-gtk
        fcitx5-lua
      ];
    };

    environment.sessionVariables = {
      QT_IM_MODULE = "fcitx";
      GTK_IM_MODULE = "fcitx";
      XMODIFIERS = "@im=fcitx";
      SDL_IM_MODULE = "fcitx";
      GLFW_IM_MODULE = "ibus";
      NIXOS_OZONE_WL = "1";
    };
  };
}
