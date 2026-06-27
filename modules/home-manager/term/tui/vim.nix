{ lib, config, inputs, pkgs, ... }:
{
  config = lib.mkIf config.programs.neovim.enable {
    programs.neovim = {
      package = inputs.nixpkgs-unstable.legacyPackages.${pkgs.stdenv.hostPlatform.system}.neovim-unwrapped;
      defaultEditor = true;
      vimdiffAlias = true;
      withNodeJs = true;
      withPython3 = true;
    };
    home.packages = [
      pkgs.lunarvim
      pkgs.stylua
      pkgs.python312Packages.flake8
      pkgs.shellcheck
      pkgs.rustup
      pkgs.gcc
      pkgs.tree-sitter
      pkgs.luajitPackages.magick
      pkgs.clang-tools
    ];
    xdg.configFile."lvim" = {
      enable = true;
      source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/nixos/confs/lvim";
    };
    xdg.configFile."nvim" = {
      enable = true;
      source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/nixos/confs/nvim";
    };
  };
}
