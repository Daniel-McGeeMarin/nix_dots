{ config, lib, pkgs, inputs, osConfig, ... }:
{
  options = {
    desktop = {
      enable = lib.mkEnableOption "Enable desktop";
    };
  };
  imports = [
    ./apps
    ./env
    ./gaming.nix
    ./japanese.nix
    ./comms.nix
    ./sync.nix
    ./office.nix
    ./media.nix
  ];
  config = lib.mkIf config.desktop.enable {
    comms.enable = lib.mkDefault true;
    office.enable = lib.mkDefault true;
    media.enable = lib.mkDefault true;
    services.flatpak.packages = [
      "com.github.tchx84.Flatseal"
    ];
    home.packages = with pkgs; [
      brightnessctl
      wl-clipboard
    ];
  };
}
