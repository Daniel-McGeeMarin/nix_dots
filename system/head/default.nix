{ config, lib, pkgs, inputs, ... }:
# The graphical stack: display manager, audio, boot splash, and the optional
# gaming extras.
#
# There is no `head.enable`. Importing this module is what turns the stack on,
# so a host either lists ../../system/head in its imports or it does not have a
# display at all. A flag would have to be threaded through every option in here
# by hand, and the moment one is missed - which is exactly what happened before -
# a "headless" machine quietly grows a compositor.
{
  options.head.gaming = lib.mkEnableOption "gaming extras (gamemode, gamescope, uinput)";

  config = {
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

    hardware.uinput.enable = lib.mkIf config.head.gaming true;
  };
}
