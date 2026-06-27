{ config, lib, pkgs, iputs, ... }:
{
  imports = [
    ./gnome.nix
    ./hyprland.nix
    ./xdg.nix
  ];
}
