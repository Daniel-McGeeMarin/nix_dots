{ config, lib, pkgs, inputs, secrets, ... }:
{
  imports = [
    inputs.home-manager.nixosModules.default
    ./head
    ./grub.nix
  ];

  networking.networkmanager.enable = true;

  # automatic-timezoned.enable — disabled until nixpkgs#321121 is resolved
  services.printing.drivers = [ pkgs.gutenprint ];

  i18n.supportedLocales = [ "all" ];

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
  ];

  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  nix.settings.auto-optimise-store = true;
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 7d";
  };
  nix.optimise = {
    automatic = true;
    dates = [ "weekly" ];
  };

  programs = {
    gnupg.agent = {
      enable = true;
      pinentryPackage = pkgs.pinentry-gtk2;
    };
    zsh.enable = true;
  };

  home-manager.extraSpecialArgs = { inherit inputs pkgs secrets; };

  services.tailscale = {
    enable = true;
    openFirewall = true;
  };

  networking.firewall.enable = lib.mkDefault true;
  fonts.fontDir.enable = true;
}
