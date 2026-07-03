{ config, lib, pkgs, inputs, ... }:
{
  imports = [
    ../../system
    ../../system/serv
    inputs.agenix.nixosModules.default
    ./hardware-configuration.nix
    ./storage.nix
  ];

  nixpkgs.config.allowUnfree = true;

  networking.hostName = "XiaServer";
  networking.hostId = "9933a4ba";

  head = {
    enable = true;
    gaming = true;
  };

  serv.enable = true;
  serv.network.enable = true;
  serv.auth.enable = true;
  serv.dashboard.enable = true;
  # serv.blogs.enable = true;  # enable after creating ghost secrets on server
  serv.ocis.enable = true;
  services.openssh.settings.PasswordAuthentication = false;

  services.displayManager.autoLogin = {
    enable = true;
    user = "XiaServer";
  };

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
    unfree.cudatoolkit
    unfree.cudaPackages.cuda_cudart
  ];

  programs = {
    hyprland.enable = true;
    nix-ld.enable = true;
    nix-ld.libraries = [];
  };

  virtualisation.docker = {
    enable = true;
    package = pkgs.docker_29;
  };

  virtualisation.oci-containers.backend = "docker";

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

  home-manager = {
    backupFileExtension = "backup";
    extraSpecialArgs = { flakeAttr = "XiaServer"; };
    users."XiaServer" = import ./home.nix;
  };

  nix.package = pkgs.lix;

  system.stateVersion = "24.11";
}
