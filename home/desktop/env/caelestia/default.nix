{ config, lib, pkgs, inputs, ... }:

let
  patched-caelestia = import ./patches {
    caelestia-shell = inputs.caelestia-shell.packages.${pkgs.stdenv.hostPlatform.system}.with-cli;
  };
in
{
  imports = [
    inputs.caelestia-shell.homeManagerModules.default
  ];

  config = lib.mkIf config.desktop.enable {
    programs.caelestia = {
      enable = true;
      package = patched-caelestia;
      systemd = {
        enable = true;
        target = "graphical-session.target";
        environment = [];
      };
      cli.enable = true;
    };

    xdg.configFile."caelestia/shell.json".source =
      config.lib.file.mkOutOfStoreSymlink
        "${config.home.homeDirectory}/nixos/home/desktop/env/caelestia/confs/shell.json";
    xdg.configFile."caelestia/shell-tokens.json".source =
      config.lib.file.mkOutOfStoreSymlink
        "${config.home.homeDirectory}/nixos/home/desktop/env/caelestia/confs/shell-tokens.json";
  };
}
