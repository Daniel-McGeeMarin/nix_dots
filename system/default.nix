{ config, lib, pkgs, inputs, secrets, ... }:
{
  imports = [
    inputs.home-manager.nixosModules.default
    ./head
    ./grub.nix
  ];

  networking.networkmanager.enable = true;
  networking.networkmanager.dns = "systemd-resolved";

  services.resolved = {
    enable = true;
    dnssec = "false";
  };

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

  # Nix's default connect-timeout of 5s covers DNS resolution too, and the first
  # lookup of a cold hostname here regularly takes longer than that. Nix then
  # retries, and the retry trips a Nix bug: the redirect github.com ->
  # codeload.github.com is seen as the URI "changing final destination during
  # transfer", which is fatal. So a slow DNS reply aborted the whole rebuild.
  # 30s is generous enough that the retry path is never entered.
  nix.settings.connect-timeout = 30;
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
