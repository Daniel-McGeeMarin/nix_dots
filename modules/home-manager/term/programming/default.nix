{ config, lib, pkgs, inputs, osConfig, ... }:
{
  imports = [
    ./python
  ];
  options = {
    programming = {
      enable = lib.mkEnableOption "Enable programming";
      R.enable = lib.mkEnableOption "Enable R";
    };
  };
  config = lib.mkIf config.programming.enable {
    programming = {
      python.enable = lib.mkDefault true;
      R.enable = lib.mkDefault true;
    };
    home.packages = with pkgs; [
      (lib.mkIf config.programming.R.enable R)
    ];
  };
}
