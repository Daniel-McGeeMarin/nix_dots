{ config, lib, pkgs, inputs, osConfig, ... }:

{
  imports = [
    ../../modules/home-manager
  ];
  programs.home-manager.enable = true;
  home.username = "ghastly";
  home.homeDirectory = "/home/ghastly";

  home.stateVersion = "23.11"; # Do not change
}
