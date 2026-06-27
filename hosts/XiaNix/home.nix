{ config, lib, pkgs, inputs, osConfig, ... }:

{
  imports = [
    #this disables my entire local homemanager config
    ../../modules/home-manager

    inputs.caelestia-shell.homeManagerModules.default
  ];
  programs.home-manager.enable = true;
  home.username = "xia";
  home.homeDirectory = "/home/xia";



  # IMPORTANT: disable your existing desktop module to avoid conflicts (hyprland, hypridle, waybar, etc.)

  sync.enable = false;
  programming.enable = true;
  ai.enable = false;
  ai.claudeCode.enable = true;
  
  desktop = {
    enable = true;
    gaming.enable = true;
    japanese.enable = false;
  };


  
  programs.caelestia = {
  enable = true;
  systemd = {
    enable = true; # if you prefer starting from your compositor
    target = "graphical-session.target";
    environment = [];
  };
    #settings = {
    #paths.wallpaperDir = "~/Images";
    #};
  cli = {
    enable = true; # Also add caelestia-cli to path
      #settings = {
      #  theme.enableGtk = false;
      #};
  };
};

  home.packages = [
    #pkgs.papirus-icon-theme

    
    # pkgs.unfree.android-studio
    # pkgs.mullvad-vpn
    pkgs.nix-output-monitor
    pkgs.fractal
    (pkgs.calibre.overrideAttrs
      (attrs: {
        preFixup = (
          builtins.replaceStrings
            [
              ''
                --prefix PYTHONPATH : $PYTHONPATH \
              ''
            ]
            [
              ''
                --prefix LD_LIBRARY_PATH : ${pkgs.libressl.out}/lib \
                --prefix PYTHONPATH : $PYTHONPATH \
              ''
            ]
            attrs.preFixup
        );
      }))
  ];


  programs = {
    password-store.enable = true;
    rbw.enable = true;
  };


  systemd.user.sessionVariables.SSH_AUTH_SOCK = "/run/user/1000/keyring/ssh"; # Makes ssh-agent work
  home.stateVersion = "23.11"; # Do not change
}
