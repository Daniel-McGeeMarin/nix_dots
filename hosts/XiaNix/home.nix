{ config, lib, pkgs, inputs, osConfig, ... }:

{
  # Both halves of the user environment. XiaServer imports only ../../home/term;
  # the desktop tree is not a flag any more, it is this line.
  imports = [
    ../../home/term
    ../../home/desktop
  ];

  programs.home-manager.enable = true;
  home.username = "xia";
  home.homeDirectory = "/home/xia";

  programming.enable = true;
  ai.enable = false;
  ai.claudeCode.enable = true;
  ai.codex.enable = true;
  ai.privatellm.enable = true;
  programs.claudeAgents.enable = true;

  desktop = {
    gaming.enable = true;
    workmic.enable = true;
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
  };

  systemd.user.sessionVariables.SSH_AUTH_SOCK = "/run/user/1000/keyring/ssh";
  home.stateVersion = "23.11"; # Do not change
}
