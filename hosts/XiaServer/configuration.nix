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
  serv.blogs.enable = true;
  serv.ocis.enable = true;
  serv.onlyoffice.enable = true;
  serv.apps.site.enable = true;
  serv.forgejo.enable = true;
  serv.graphide.enable = false;
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
    inputs.agenix.packages.x86_64-linux.default
  ];

  programs = {
    hyprland.enable = true;
    nix-ld.enable = true;
    nix-ld.libraries = [];
  };

  virtualisation.podman = {
    enable = true;
    dockerCompat = true;
    defaultNetwork.settings.dns_enabled = true;
  };

  virtualisation.oci-containers.backend = "podman";

  # Workaround for nixos-rebuild-ng bug: systemd-run --collect never fires the
  # "unit removed" D-Bus event when the transient unit file persists on disk,
  # causing nixos-rebuild to hang indefinitely after switch-to-configuration
  # completes. This path unit watches for the file and cleans it up.
  systemd.paths."nixos-rebuild-cleanup" = {
    wantedBy = [ "multi-user.target" ];
    pathConfig.PathExists = "/run/systemd/transient/nixos-rebuild-switch-to-configuration.service";
  };
  systemd.services."nixos-rebuild-cleanup" = {
    description = "Unblock nixos-rebuild-ng after switch-to-configuration completes";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = toString (pkgs.writeShellScript "nixos-rebuild-cleanup" ''
        for i in $(seq 1 120); do
          if ! systemctl is-active nixos-rebuild-switch-to-configuration.service &>/dev/null; then
            break
          fi
          sleep 1
        done
        sleep 2
        rm -f /run/systemd/transient/nixos-rebuild-switch-to-configuration.service
        systemctl daemon-reload
      '');
    };
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
    extraGroups = [ "wheel" "video" "input" ];
  };

  home-manager = {
    backupFileExtension = "backup";
    extraSpecialArgs = { flakeAttr = "XiaServer"; };
    users."XiaServer" = import ./home.nix;
  };

  nix.package = pkgs.lix;

  system.stateVersion = "24.11";
}
