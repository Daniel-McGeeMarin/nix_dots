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
      fastfetch
      libnotify
      jq
    ];
    programs.gpg.enable = true;
  };
}
