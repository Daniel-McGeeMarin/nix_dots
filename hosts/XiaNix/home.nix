{ config, lib, pkgs, inputs, osConfig, ... }:

{
  imports = [
    ../../modules/home-manager
    inputs.illogical-flake.homeManagerModules.default
  ];
  programs.home-manager.enable = true;
  home.username = "xia";
  home.homeDirectory = "/home/xia";
  sync.enable = false;
  programming.enable = true;
  ai.enable = false;
  #desktop = {
  #  enable = true;
  #  gaming.enable = true;
  #  japanese.enable = false;
  #};
  

  # IMPORTANT: disable your existing desktop module to avoid conflicts (hyprland, hypridle, waybar, etc.)
  desktop = {
    enable = false;
    gaming.enable = false;
    japanese.enable = false;
  };

  programs.illogical-impulse = {
    enable = true;

    # Customize shell tools (all enabled by default)
    dotfiles = {
      fish.enable = true;     # Fish shell with custom config
      kitty.enable = true;    # Kitty terminal emulator
      starship.enable = true; # Starship prompt
    };
    
    # Hyprland Plugins (Declarative installation & loading)
    hyprland.plugins = [
      pkgs.hyprlandPlugins.hyprbars
      pkgs.hyprlandPlugins.hyprexpo
      # Add any other plugins available in nixpkgs
    ];
  };

  home.packages = [
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

  services.flatpak = {
    packages = [
      #"com.calibre_ebook.calibre"
      "io.missioncenter.MissionCenter"
      "net.cozic.joplin_desktop"
    ];
  };


  systemd.user.sessionVariables.SSH_AUTH_SOCK = "/run/user/1000/keyring/ssh"; # Makes ssh-agent work
  home.stateVersion = "23.11"; # Do not change
}
