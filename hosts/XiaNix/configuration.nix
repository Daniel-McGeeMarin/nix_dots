{ config, lib, pkgs, inputs, ... }:
let
  hostIdentityMarker = "/var/lib/nixos-host-identity";
  expectedHost = "XiaNix";
  markerExists = (builtins.tryEval (builtins.pathExists hostIdentityMarker)).value or false;
  markerContent = if markerExists then ((builtins.tryEval (builtins.readFile hostIdentityMarker)).value or "") else "";
  currentIdentity = lib.removeSuffix "\n" markerContent;
in
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

  assertions = [
    {
      assertion = currentIdentity == "" || currentIdentity == expectedHost;
      message = ''
        Host-identity guard: refusing to build closure for '${expectedHost}'.
        ${hostIdentityMarker} says this machine is '${currentIdentity}'.
        You almost certainly ran
            nixos-rebuild switch --flake .#${expectedHost}
        on the wrong box. Did you mean .#${currentIdentity}?
        If you truly want to reconfigure this machine's identity, run
            sudo rm ${hostIdentityMarker}
        and rebuild again.
      '';
    }
  ];

  system.activationScripts.hostIdentityMarker.text = ''
    [ -f ${hostIdentityMarker} ] || echo ${expectedHost} > ${hostIdentityMarker}
  '';
  networking.extraHosts = "127.0.0.1 host.docker.internal";
  # Allow Podman bridge containers (supabase_network_graphide → podman1) to
  # reach host services like auth-shim on :8081 for the OAuth token exchange.
  networking.firewall.trustedInterfaces = [ "podman1" ];

  head = {
    enable = true;
    gaming = true;
  };

  # Exclude tailscaled from the Mullvad tunnel so Tailscale P2P/DERP works.
  # The split-tunnel exclusion is PID-scoped, so we re-add it every time
  # either daemon (re)starts.
  systemd.services.mullvad-tailscale-exclude = {
    description = "Exclude tailscaled PID from Mullvad split tunnel";
    after = [ "mullvad-daemon.service" "tailscaled.service" ];
    bindsTo = [ "mullvad-daemon.service" "tailscaled.service" ];
    wantedBy = [ "tailscaled.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = pkgs.writeShellScript "mullvad-exclude-tailscale" ''
        PID=$(${pkgs.procps}/bin/pgrep -x tailscaled)
        ${pkgs.mullvad}/bin/mullvad split-tunnel add "$PID"
      '';
      ExecStop = pkgs.writeShellScript "mullvad-unexclude-tailscale" ''
        ${pkgs.mullvad}/bin/mullvad split-tunnel clear
      '';
    };
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
