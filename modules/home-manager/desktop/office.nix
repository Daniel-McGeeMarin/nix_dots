{ lib, config, pkgs, ... }:
{
  options = {
    office = {
      enable = lib.mkEnableOption "Enable office";
    };
  };
  config = lib.mkIf config.office.enable {
    programs.zathura.enable = lib.mkDefault true;
    home.packages = with pkgs; [
      speedcrunch
      texliveFull
      libreoffice-qt
      hunspell
      anki-bin
    ];
  };
}
