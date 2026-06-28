{ lib, config, pkgs, ... }:
{
  options = {
    sync = {
      enable = lib.mkEnableOption "Enable sync";
    };
  };
  config = lib.mkIf config.sync.enable {
    home.packages = [
      pkgs.blueberry
    ];
    services.kdeconnect = {
      enable = true;
      indicator = true;
    };
  };
}
