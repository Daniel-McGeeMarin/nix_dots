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
      # Slimmed from texliveFull (~7G, 15k+ store paths) to scheme-small plus
      # the common collections that cover the vast majority of documents.
      # Add more collections here if a build complains about a missing package.
      (texlive.combine {
        inherit (texlive)
          scheme-small
          collection-latexrecommended
          collection-latexextra
          collection-fontsrecommended
          collection-mathscience
          collection-bibtexextra;
      })
      libreoffice-qt
      hunspell
      anki-bin
    ];
  };
}
