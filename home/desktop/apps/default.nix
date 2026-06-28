{ config, lib, pkgs, inputs, osConfig, ... }:
{
  imports = [
    ./firefox.nix
    ./foot.nix
    ./kitty.nix
    ./mpv.nix
    ./ncmpcpp.nix
    ./zathura.nix
  ];
  config = lib.mkIf config.desktop.enable {
    home.packages = with pkgs; [
      brave
      #firefox
      #code-cursor
      vscodium

      syncplay # synchronized playback with mpv (see programs.mpv)
      (lib.mkIf ((osConfig.services or { }).pipewire.enable or false) helvum)
      (lib.mkIf ((osConfig.services or { }).pipewire.pulse.enable or false) pavucontrol)
    ];
    programs = {
      #Moved to firefox.nix 
      #librewolf.enable = lib.mkDefault true;
      foot.enable = lib.mkDefault true;
      kitty.enable = lib.mkDefault true;
      zathura.enable = lib.mkDefault true;
      mpv.enable = lib.mkDefault true;
    };

    xdg.mimeApps.defaultApplications = {
      "text/html" = "brave-browser.desktop";
      "x-scheme-handler/http" = "brave-browser.desktop";
      "x-scheme-handler/https" = "brave-browser.desktop";
    };

 

    


  };
}
