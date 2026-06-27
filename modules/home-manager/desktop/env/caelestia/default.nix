{ config, lib, ... }:
{
  # Keep caelestia's user settings (shell.json) inside this repo so a fresh
  # `git pull` brings them along. An out-of-store symlink is used (same pattern
  # as nvim) so caelestia's control-center can still write to the file live.
  config = lib.mkIf (config.programs.caelestia.enable or false) {
    xdg.configFile."caelestia/shell.json".source =
      config.lib.file.mkOutOfStoreSymlink
        "${config.home.homeDirectory}/nixos/modules/home-manager/desktop/env/caelestia/confs/shell.json";
    xdg.configFile."caelestia/shell-tokens.json".source =
      config.lib.file.mkOutOfStoreSymlink
        "${config.home.homeDirectory}/nixos/modules/home-manager/desktop/env/caelestia/confs/shell-tokens.json";
  };
}
