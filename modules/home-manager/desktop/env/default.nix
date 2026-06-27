{ config, lib, pkgs, iputs, ... }:
{
  imports = [
    ./caelestia.nix
    ./gnome.nix
    ./hyprland.nix
    ./xdg.nix
  ];
}
