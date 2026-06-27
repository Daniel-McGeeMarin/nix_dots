{ config, lib, pkgs, inputs, ... }:

let
  upkgs = pkgs.unstable;
in
{
  imports = [
    ./plymouth.nix
    ./grub-theme.nix
    ./gram.nix
  ];

  options.head = {
    enable = lib.mkEnableOption "Set if headed system";
    gaming = lib.mkEnableOption "Enable gaming";
    gram = lib.mkEnableOption "LG Gram hardware quirks";
  };

  config = lib.mkIf config.head.enable {
    boot.plymouth.enable = lib.mkDefault true;

    services = {
      pulseaudio.enable = false;
      pipewire = {
        enable = true;
        alsa.enable = true;
        alsa.support32Bit = true;
        pulse.enable = true;
      };
      displayManager.gdm = {
        enable = true;
        wayland = true;
      };
    };

    programs = lib.mkIf config.head.gaming {
      gamemode.enable = true;
      gamescope.enable = true;
    };

    fonts.fontDir.enable = true;
    hardware.uinput.enable = lib.mkIf config.head.gaming true;
  };
}
