{ config, lib, pkgs, inputs, ... }:

let
  upkgs = pkgs.unstable;
in
{
  imports =
    [
      ./hardware-configuration.nix
      ../../modules/nixos
    ];
  services.home-assistant.enable = true;
  services.mullvad-vpn.enable = true;
  serv = {
    enable = true;
    media.enable = true;
  };
  services.openssh = {
    enable = true;
    ports = [ 22 ];
    settings = {
      PasswordAuthentication = true;
      AllowUsers = "ghastly"; # Allows all users by default. Can be [ "user1" "user2" ]
      UseDns = true;
      X11Forwarding = false;
      PermitRootLogin = "prohibit-password"; # "yes", "without-password", "prohibit-password", "forced-commands-only", "no"
    };
  };

  networking.hostName = "nixos";

  time.timeZone = "America/New_York";

  users.users.ghastly = {
    isNormalUser = true;
    shell = pkgs.zsh;
    extraGroups = [ "wheel" ];
  };

  home-manager = {
    users."ghastly" = import ./home.nix;
  };
  system.stateVersion = "23.11"; # DO NOT CHANGE
  system.autoUpgrade = {
    enable = true;
    flake = inputs.self.outPath;
    flags = [
      "--update-input"
      "nixpkgs"
      "-L" # print build logs
    ];
    dates = "02:00";
    randomizedDelaySec = "45min";
  };
}
