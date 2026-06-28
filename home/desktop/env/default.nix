{ config, lib, pkgs, inputs, ... }:
{
  imports = [
    ./caelestia
    ./gnome.nix
    ./hyprland.nix
    ./xdg.nix
  ];
}
