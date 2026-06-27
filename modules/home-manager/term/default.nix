{ config, lib, pkgs, inputs, osConfig, ... }:
{
  imports = [
    ./programming
    ./tui
    ./ai.nix
    ./zsh.nix
    ./media.nix
  ];
  config = {
    tui.enable = lib.mkDefault true;
    home.packages = with pkgs; [
      (lib.mkIf config.desktop.enable brightnessctl)
      (lib.mkIf config.desktop.enable wl-clipboard)
      fastfetch
      libnotify
      jq
      yt-dlp
    ];
    programs.gpg.enable = true;
  };
}
