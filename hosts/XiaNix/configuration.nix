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
    # This host has a screen, so it takes the graphical stack. XiaServer omits
    # this line and imports ../../system/serv instead.
    ../../system/head
    ./hardware-configuration.nix
    ./gram.nix
    ./resources.nix
  ];

  boot.extraModprobeConfig = ''
    options snd-hda-intel model=alc298-samsung-amp2
  '';
  boot.extraModulePackages = with config.boot.kernelPackages; [ v4l2loopback ];
  boot.kernelModules = [ "binder_linux" ];
  # Run aarch64 binaries through qemu-user, so this laptop can build the
  # HackerPi SD image (nix build .#hackerpi-image). Emulated, so that build
  # is slow -- but it only happens when the Pi's system changes.
  boot.binfmt.emulatedSystems = [ "aarch64-linux" ];

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

  # Keep Supabase's ports out of the kernel's outbound-connection pool.
  #
  # The Graphide dev stack has Supabase listen on 54321-54327, and this
  # kernel's ephemeral range (net.ipv4.ip_local_port_range) is 32768-60999 --
  # which contains them. So any program making an OUTGOING connection can be
  # handed one of Supabase's ports as its source port, and while that
  # connection lives, nothing can listen there. `nix run .#gr-srv` then dies
  # with `rootlessport listen tcp 0.0.0.0:54324: bind: address already in
  # use`, with no stale stack to blame and nothing to kill.
  #
  # It is not always the brief TIME-WAIT that gr-srv's guard assumes and waits
  # out. On 2026-09-08 the holder was a long-lived HTTPS connection to an API
  # that had taken 54326 and kept it for the length of the session, so the
  # 90-second wait could never have cleared it.
  #
  # Reserving the range is the standing cure gr-srv itself recommends: the
  # kernel simply never hands these out as ephemeral source ports. A little
  # wider than 54321-54327 so a future Supabase service that claims one more
  # port does not reintroduce this quietly.
  boot.kernel.sysctl."net.ipv4.ip_local_reserved_ports" = "54320-54330";

  head.gaming = true;

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
  # Rootless podman's systemd user socket ($XDG_RUNTIME_DIR/podman/podman.sock),
  # which the Graphide dev stack (`nix run .#gr-srv`) uses when present.
  #
  # The socket is the point, not the CLI. Agents run inside Orca's bubblewrap
  # sandbox, which has its own /etc without /etc/subuid and sets no_new_privs,
  # so the setuid newuidmap cannot run there. A `podman system service` started
  # from an agent shell gets a one-uid map (`0 1000 1`) and Postgres fails with
  # `crun: mkdir /var/lib/postgresql/data: Permission denied`, even though the
  # subuid range on xia below exists. The user systemd manager runs outside the
  # sandbox, so its service gets the range. dockerCompat/dockerSocket stay off:
  # they conflict with docker above. See the crun entry in monolith's QUIRKS.md.
  virtualisation.podman.enable = true;
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

    # Signal is installed per-user via Home Manager, but it ships polkit action
    # definitions (org.signalapp.*) that its backup/export flows authenticate
    # against. polkitd only reads actions out of the *system* profile, so from a
    # Home Manager install those actions are never registered and every request
    # fails with "an error occurred while requesting system authentication".
    # Installing it here too registers them; same store path, so no extra cost.
    # Keep in sync with home/desktop/default.nix.
    unstable.signal-desktop
  ];

  time.timeZone = "America/Los_Angeles";

  users.users.xia = {
    isNormalUser = true;
    shell = pkgs.zsh;
    extraGroups = [ "adbusers" "docker" "wheel" "uinput" "input" "video" "lxc" ];
    # Rootless podman needs a subordinate uid/gid range to map container users
    # other than root. Without one (/etc/subuid did not exist on this host until
    # 2026-09-12) every such user became `nobody` on disk: the Supabase
    # postgres container could not create /var/lib/postgresql/data, and the
    # files containers did write could only be removed by root. See the two
    # rootless-podman entries in the monorepo's QUIRKS.md. After the rebuild:
    # `podman system migrate`, and recreate the dev database volume
    # (`podman volume rm supabase_db_graphide`).
    autoSubUidGidRange = true;
  };

  home-manager = {
    backupFileExtension = "backup2";
    extraSpecialArgs = { flakeAttr = "XiaNix"; };
users."xia" = import ./home.nix;
  };

  nix.package = pkgs.lix;

  system.stateVersion = "23.11"; # DO NOT CHANGE
}
