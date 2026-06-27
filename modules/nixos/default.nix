{ config, lib, pkgs, inputs, secrets, ... }:

let
  upkgs = pkgs.unstable;
in
{
  imports =
    [
      inputs.home-manager.nixosModules.default
      ./head
      ./serv
     # ./grub.nix #comment out to disable grub
    ];

  
 # boot.loader.systemd-boot.enable = false;

  #Disable if running in grub 
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  networking.networkmanager.enable = true;

  services = {
    # automatic-timezoned.enable = true; # Re-Enable once https://github.com/NixOS/nixpkgs/issues/321121 closes
    printing = {
      drivers = [
        pkgs.gutenprint
      ];
    };
    # avahi = {
    #   # Networking stuff
    #   enable = true;
    #   nssmdns4 = true;
    # };
  };

  i18n.supportedLocales = [ "all" ]; # Support all languages

  security.rtkit.enable = true;
  environment.systemPackages = with pkgs; [
    neovim
    pciutils
    htop
    wget
    home-manager
    pinentry-gtk2
    git
    unzip
    ripgrep
    fzf

    inputs.zen-browser.packages.${pkgs.stdenv.hostPlatform.system}.default
  ];

  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  programs = {
    gnupg.agent = {
      enable = true;
      pinentryPackage = pkgs.pinentry-gtk2;
    };
    zsh.enable = true;
  };
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 7d";
  };
  # Deduplicate identical files in the store via hardlinks. With multiple
  # nixpkgs/toolchains this reclaims a lot; runs incrementally on each build
  # plus a weekly full pass.
  nix.settings.auto-optimise-store = true;
  nix.optimise = {
    automatic = true;
    dates = [ "weekly" ];
  };
  home-manager = {
    # also pass inputs and secrets to home-manager modules
    extraSpecialArgs = { inherit inputs pkgs secrets; };
  };
  networking.firewall = {
    enable = lib.mkDefault true;
  };
  fonts.fontDir.enable = true;
}
