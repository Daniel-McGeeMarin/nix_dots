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



    programs.direnv = {
      enable = true;
      nix-direnv.enable = true;
      enableZshIntegration = true; # Set to true if you use zsh
      enableBashIntegration = true; # Set to true if you use bash
      silent = true;
    };



    home.packages = with pkgs; [
      nodejs
      (lib.mkIf config.programming.R.enable R)
    ];
  };
}
