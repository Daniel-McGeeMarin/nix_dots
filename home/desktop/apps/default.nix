{ config, lib, pkgs, inputs, osConfig, ... }:
{
  imports = [
    ./zen.nix
    ./foot.nix
    ./kitty.nix
    ./mpv.nix
    ./ncmpcpp.nix
    ./zathura.nix
  ];

  config = lib.mkIf config.desktop.enable {

    programs = {
      foot.enable = lib.mkDefault true;
      kitty.enable = lib.mkDefault true;
      zathura.enable = lib.mkDefault true;
      mpv.enable = lib.mkDefault true;
    };

    xdg.mimeApps.defaultApplications = {
      "text/html" = "zen-beta.desktop";
      "x-scheme-handler/http" = "zen-beta.desktop";
      "x-scheme-handler/https" = "zen-beta.desktop";
    };
  };
}
