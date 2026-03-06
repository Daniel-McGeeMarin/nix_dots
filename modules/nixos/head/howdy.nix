{ config, lib, pkgs, inputs, ... }:

let
  howdyPkgs = import inputs.nixpkgs-howdy {
    inherit (pkgs) system;
    config.allowUnfree = true;
  };
in {
  imports = [
    "${inputs.nixpkgs-howdy}/nixos/modules/services/security/howdy/default.nix"
  ];

  options.head = {
    howdy = {
      enable = lib.mkEnableOption "Howdy face authentication";
    };
  };



  config = lib.mkIf config.head.howdy.enable {


    services.howdy = {
      enable = true;
      package = howdyPkgs.howdy;
      settings = {
        video = {
          device_path = "/dev/video2";
          dark_threshold = 60;
        };
        core = {
          detection_notice = false;
        };
      };
    };

    # PAM: Howdy for lock screens and login
    security.pam.services = {
      swaylock.rules.auth.howdy = {
        order = 1;
        control = "sufficient";
        modulePath = "${howdyPkgs.howdy}/lib/security/pam_howdy.so";
      };

      hypridle.rules.auth.howdy = {
        order = 1; # Ensure it runs first
        control = "sufficient";
        modulePath = "${howdyPkgs.howdy}/lib/security/pam_howdy.so";
      };

      # ADDING SUDO HERE: This lets you test without locking your screen
      sudo.rules.auth.howdy = {
        order = 1;
        control = "sufficient";
        modulePath = "${howdyPkgs.howdy}/lib/security/pam_howdy.so";
      };

      login.rules.auth.howdy = {
        order = 1;
        control = "sufficient";
        modulePath = "${howdyPkgs.howdy}/lib/security/pam_howdy.so";
      };

    };

    users.users.xia.extraGroups = [ "video"];
  };
}
