{ config, lib, pkgs, inputs, ... }:

let
  upkgs = pkgs.unstable;
in
{
  imports =
    [
      ../../modules/nixos
      ./hardware-configuration.nix


      #../../modules/nixos/onTheGo.nix

    ];


  # new fix for sound error

  boot.extraModprobeConfig = ''
    options snd-hda-intel model=alc298-samsung-amp2
  '';


  networking.hostName = "XiaNix";
  #networking.networkmanager.enable = true;
  head = {
    enable = true;
    gaming = true;
    howdy.enable = true;
  };
  programs = {

    hyprland.enable = true;
    adb.enable = true;
    nix-ld.enable = true;
    nix-ld.libraries = with pkgs; [

      # Add any missing dynamic libraries for unpackaged programs

      # here, NOT in environment.systemPackages

    ];
    kdeconnect.enable = true;
    noisetorch.enable = true;
  };

  virtualisation.docker = {
  enable = true;
  # optional: allow your user to use Docker without sudo
    #enableOnBoot = true;
  };

  virtualisation.waydroid.enable = true;



  fonts.packages = with pkgs; [
    rubik
    nerd-fonts.ubuntu
    nerd-fonts.fira-code
    nerd-fonts.droid-sans-mono
    nerd-fonts.jetbrains-mono
    noto-fonts-cjk-sans
    source-han-sans
    source-han-mono
    source-han-serif
    source-han-sans-vf-ttf
    source-han-sans-vf-otf

  ];


  time.timeZone = "America/Los_Angeles";
  services = {
    flatpak.enable = true;
    mullvad-vpn.enable = true;

    printing.enable = true;
    fwupd.enable = true;
    fprintd.enable = true;
    thermald.enable = true;
    geoclue2.enable = true;
    upower.enable = true;


    xserver = {
      enable = true;
      desktopManager.gnome.enable = true;
    };
  };

  environment.systemPackages = with pkgs; [
    
    wireguard-tools
    libusb1
    powertop
    numworks-udev-rules
    blueman
    alsa-utils
    kdePackages.breeze-icons
    kdePackages.breeze-icons


  ];


  users.users.xia = {
    isNormalUser = true;
    shell = pkgs.zsh;
    extraGroups = [ "adbusers" "docker" "wheel" "uinput" "input" "video" "lxc"]; # Enable ‘sudo’ for the user.
  };
  boot.extraModulePackages = with config.boot.kernelPackages; [
    v4l2loopback
  ];

  boot.kernelModules = [ "binder_linux" ];

  
  home-manager.backupFileExtension = "backup2";





  home-manager = {
    users."xia" = import ./home.nix;
  };


  nix.package = pkgs.lix;

 

  system.stateVersion = "23.11"; # DO NOT CHANGE
}
