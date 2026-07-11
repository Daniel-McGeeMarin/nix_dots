{ config, lib, pkgs, inputs, ... }:
{
  imports = [
    ../../system
    ./hardware-configuration.nix
    ./gram.nix
  ];

  boot.extraModprobeConfig = ''
    options snd-hda-intel model=alc298-samsung-amp2
  '';
  boot.extraModulePackages = with config.boot.kernelPackages; [ v4l2loopback ];
  boot.kernelModules = [ "binder_linux" ];

  networking.hostName = "XiaNix";

  head = {
    enable = true;
    gaming = true;
  };

  services = {
    flatpak.enable = true;
    mullvad-vpn.enable = true;
    printing.enable = true;
    fwupd.enable = true;
    fprintd.enable = true;
    thermald.enable = true;
    geoclue2.enable = true;
    upower.enable = true;
    desktopManager.gnome.enable = true;
    xserver.enable = true;
    displayManager.autoLogin = {
      enable = true;
      user = "xia";
    };
  };

  programs = {
    hyprland.enable = true;
    adb.enable = true;
    nix-ld.enable = true;
    nix-ld.libraries = [];
    kdeconnect.enable = true;
    noisetorch.enable = true;
  };

  virtualisation.docker = {
    enable = true;
    package = pkgs.docker_29;
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

  environment.systemPackages = with pkgs; [
    wireguard-tools
    libusb1
    powertop
    numworks-udev-rules
    blueman
    alsa-utils
    kdePackages.breeze-icons
  ];

  time.timeZone = "America/Los_Angeles";

  users.users.xia = {
    isNormalUser = true;
    shell = pkgs.zsh;
    extraGroups = [ "adbusers" "docker" "wheel" "uinput" "input" "video" "lxc" ];
  };

  home-manager = {
    backupFileExtension = "backup2";
    extraSpecialArgs = { flakeAttr = "XiaNix"; };
users."xia" = import ./home.nix;
  };

  nix.package = pkgs.lix;

  system.stateVersion = "23.11"; # DO NOT CHANGE
}
