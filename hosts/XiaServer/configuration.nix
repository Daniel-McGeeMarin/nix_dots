{ config, lib, pkgs, inputs, ... }:

{
  imports = [
    ../../nixos
    ./hardware-configuration.nix
  ];

  nixpkgs.config.allowUnfree = true;

  networking.hostName = "XiaServer";

  head = {
    enable = true;
    gaming = true;
  };

  services.displayManager.autoLogin = {
    enable = true;
    user = "XiaServer";
  };

  serv.enable = true;

  # NVIDIA 1080 Ti — standalone GPU, no PRIME
  services.xserver.videoDrivers = [ "nvidia" ];
  hardware.graphics = {
    enable = true;
    enable32Bit = true;
  };
  hardware.nvidia = {
    modesetting.enable = true;
    powerManagement.enable = false;
    open = false;
    nvidiaSettings = true;
    package = config.boot.kernelPackages.nvidiaPackages.stable;
  };
  environment.systemPackages = with pkgs; [
    pkgs.unfree.cudatoolkit
    pkgs.unfree.cudaPackages.cuda_cudart
  ];
  nixpkgs.config.cudaSupport = true;

  programs = {
    hyprland.enable = true;
    nix-ld.enable = true;
    nix-ld.libraries = [];
  };

  virtualisation.docker = {
    enable = true;
    package = pkgs.docker_29;
  };

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
  ];

  time.timeZone = "America/Los_Angeles";

  users.users.XiaServer = {
    isNormalUser = true;
    shell = pkgs.zsh;
    extraGroups = [ "docker" "wheel" "video" "input" ];
  };

  home-manager.backupFileExtension = "backup";
  home-manager.users."XiaServer" = import ./home.nix;

  nix.package = pkgs.lix;

  system.stateVersion = "24.11";
}
