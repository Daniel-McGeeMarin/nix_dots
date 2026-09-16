{ config, lib, pkgs, inputs, secrets, ... }:
{
  # ./head (the graphical stack) and ./serv (the server stack) are NOT imported
  # here. A host picks one by importing it, the same way hosts/XiaServer imports
  # ../../system/serv. Importing the tree IS the switch - see the note at the top
  # of ./head.
  imports = [
    inputs.home-manager.nixosModules.default
    ./grub.nix
  ];

  # Lives here rather than in ./head, where it used to sit, because it is not a
  # display concern: it picks the systemd-based initrd over the old scripted one,
  # and on a LUKS root the initrd is what prompts for the passphrase at boot.
  # Both hosts have a LUKS root and both want the same behaviour.
  boot.initrd.systemd.enable = lib.mkDefault true;

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

  # "warning: Git tree '/home/xia/nixos' is dirty", twice per command, on every
  # rebuild. This flake is edited in place and is essentially never clean, so
  # the warning never carries information -- it just pushes the real output of
  # a failed build off the top of the terminal.
  nix.settings.warn-dirty = false;
  nix.gc = {
    automatic = true;
    dates = "daily";
    options = "--delete-older-than 7d";
  };
  nix.optimise = {
    automatic = true;
    dates = [ "weekly" ];
  };

  # Automatic mid-build GC is OFF. The daily timer above is the only collector.
  #
  # History: min-free was raised 5 -> 20 GB on 2026-09-14 because /tmp shares
  # the root partition and at 5 GB the store filled it to 0 bytes free while
  # ~20 Claude sessions wrote scratch files (35 "command output was lost"
  # failures in one week). That backfired. A 126 GB root holding a 75 GB store
  # cannot get 20 GB below the floor, so every single store write - every
  # build, every nix develop, every editor launch - started a GC that scanned
  # the whole store, found nothing deletable (all of it was still referenced by
  # live generations), and blocked meanwhile. On 2026-09-15 that stall ran long
  # enough to time out home-manager's activation mid-switch, which removed the
  # user profile's package set and did not put the new one back.
  #
  # Root is moving to the 507 GB partition on nvme0n1, where the disk-full
  # scenario the floor defended against does not arise. If root ever ends up
  # tight again, re-enable it with a floor small enough to actually be
  # reachable - min-free below (partition size - store size), not above it.
  nix.settings.min-free = 0;
  nix.settings.max-free = 0;

  # The journal had grown to 3.4 GB: the default cap is 10% of the filesystem,
  # which on a 126 GB root is 12.6 GB before it would ever rotate.
  services.journald.extraConfig = ''
    SystemMaxUse=500M
    SystemMaxFileSize=50M
  '';

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
