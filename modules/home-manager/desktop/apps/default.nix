{ config, lib, pkgs, iputs, osConfig, ... }:
{
  imports = [
    ./qutebrowser.nix
    ./firefox.nix
    ./foot.nix
    ./kitty.nix
    ./mpv.nix
    ./zathura.nix
  ];
  config = lib.mkIf config.desktop.enable {
    home.packages = with pkgs; [
      brave
      #firefox
      #code-cursor

      bitwarden
      (lib.mkIf osConfig.services.pipewire.enable helvum)
      (lib.mkIf osConfig.services.pipewire.pulse.enable pavucontrol)
    ];
    programs = {
      #Moved to firefox.nix 
      #librewolf.enable = lib.mkDefault true;
      foot.enable = lib.mkDefault true;
      kitty.enable = lib.mkDefault true;
      zathura.enable = lib.mkDefault true;
      mpv.enable = lib.mkIf config.media.enable (lib.mkDefault true);
    };

    xdg.mimeApps.defaultApplications = {
      "text/html" = "org.qutebrowser.qutebrowser.desktop";
      "x-scheme-handler/http" = "org.qutebrowser.qutebrowser.desktop";
      "x-scheme-handler/https" = "org.qutebrowser.qutebrowser.desktop";
    };

 

    


  };
}
