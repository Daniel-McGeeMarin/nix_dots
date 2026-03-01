{ config, lib, pkgs, inputs, osConfig, secrets, ... }:
{
  imports = [
    ./desktop
    ./term
    ./rice.nix
    inputs.nix-flatpak.homeManagerModules.nix-flatpak
  ];
  options = {
    media = {
      enable = lib.mkEnableOption "Enable media";
    };
  };
}
