{ config, lib, pkgs, inputs, ... }:

{
  imports = [
    ../../home
  ];

  programs.home-manager.enable = true;
  home.username = "XiaServer";
  home.homeDirectory = "/home/XiaServer";

  desktop = {
    enable = true;
    gaming.enable = true;
  };

  programming.enable = true;
  ai.enable = false;
  ai.claudeCode.enable = true;

  home.packages = with pkgs; [
    nix-output-monitor
  ];

  home.stateVersion = "24.11";
}
