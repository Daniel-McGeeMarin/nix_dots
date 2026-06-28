{ config, lib, pkgs, inputs, osConfig, ... }:
{
  imports = [
    ./vim.nix
    ./newsboat.nix
  ];
  options = {
    tui = {
      enable = lib.mkEnableOption "Enable tui apps";
    };
  };
  config = lib.mkIf config.tui.enable {
    programs.newsboat.enable = lib.mkIf config.desktop.enable (lib.mkDefault true);
    home.packages = with pkgs; [
      btop
      unfree.ytfzf
    ];
  };
}
