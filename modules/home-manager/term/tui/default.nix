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
    programs.neovim.enable = lib.mkDefault true;
    programs.newsboat.enable = lib.mkIf config.desktop.enable (lib.mkDefault true);
    home.packages = with pkgs; [
      btop
      (lib.mkIf config.media.enable ncmpcpp)
      (lib.mkIf config.media.enable unfree.ytfzf)
    ];
  };
}
