{ config, lib, pkgs, inputs, osConfig, ... }:

{
  imports = [
    ../../home
  ];

  programs.home-manager.enable = true;
  home.username = "xia";
  home.homeDirectory = "/home/xia";

  sync.enable = false;
  programming.enable = true;
  ai.enable = false;
  ai.claudeCode.enable = true;

  desktop = {
    enable = true;
    gaming.enable = true;
  };

  home.packages = [
    pkgs.nix-output-monitor
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
    zsh.shellAliases.fixaudio = "sudo ~/nixos/hosts/XiaNix/lg-gram-audio.sh";
  };

  systemd.user.sessionVariables.SSH_AUTH_SOCK = "/run/user/1000/keyring/ssh";
  home.stateVersion = "23.11"; # Do not change
}
