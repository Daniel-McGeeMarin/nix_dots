{ config, lib, pkgs, inputs, ... }:
{
  options.desktop.japanese = {
    enable = lib.mkEnableOption "Enable Japanese";
    input.enable = lib.mkEnableOption "Enable japanese input";
  };
  config = lib.mkIf config.desktop.japanese.enable {
    desktop.japanese.input.enable = lib.mkDefault true;
    home.packages = with pkgs;
      [
        (lib.mkIf config.media.enable mokuro)
        noto-fonts-cjk-sans
        source-han-sans
        source-han-mono
        source-han-serif
        source-han-sans-vf-ttf
        source-han-sans-vf-otf
      ];
    home.sessionVariables = lib.mkIf config.desktop.japanese.input.enable {
      QT_IM_MODULE = "fcitx";
    };
    i18n.inputMethod = lib.mkIf config.desktop.japanese.input.enable {
      enabled = "fcitx5";
      fcitx5.addons = with pkgs; [
        fcitx5-mozc-ut
        fcitx5-gtk
        fcitx5-configtool
      ];
    };
    xdg.dataFile = lib.mkIf config.desktop.japanese.input.enable {
      "fcitx5/themes".source = inputs.fcitx5-gruvbox;
    };
  };
}
