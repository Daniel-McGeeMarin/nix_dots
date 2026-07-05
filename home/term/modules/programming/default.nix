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
      # R pulls ~1G; install on-demand with `nix-shell -p R` when needed.
      R.enable = lib.mkDefault false;
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
      gh
      (lib.mkIf config.programming.R.enable R)
    ];
  };
}
