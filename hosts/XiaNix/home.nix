{ config, lib, pkgs, inputs, osConfig, ... }:

{
  imports = [
    ../../modules/home-manager
  ];
  programs.home-manager.enable = true;
  home.username = "xia";
  home.homeDirectory = "/home/xia";
  sync.enable = false;
  programming.enable = true;
  ai.enable = false;
  desktop = {
    enable = true;
    gaming.enable = true;
    japanese.enable = true;
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
  systemd.user.sessionVariables.SSH_AUTH_SOCK = "/run/user/1000/keyring/ssh"; # Makes ssh-agent work
  home.stateVersion = "23.11"; # Do not change
}
