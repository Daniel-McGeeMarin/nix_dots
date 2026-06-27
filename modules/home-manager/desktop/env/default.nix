{ config, lib, pkgs, inputs, ... }:
{
  imports = [
    ./caelestia.nix
    ./gnome.nix
    ./hyprland.nix
    ./xdg.nix
  ];
}
