{ lib, config, pkgs, ... }:
{
  options = {
    comms = {
      enable = lib.mkEnableOption "Enable communications";
    };
  };
  config = lib.mkIf config.comms.enable {
    home.packages = [
      pkgs.signal-desktop
    ];
  };
}
