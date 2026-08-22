{ config, lib, pkgs, inputs, ... }:
let
  hostIdentityMarker = "/var/lib/nixos-host-identity";
  expectedHost = "XiaServer";
  markerExists = (builtins.tryEval (builtins.pathExists hostIdentityMarker)).value or false;
  markerContent = if markerExists then ((builtins.tryEval (builtins.readFile hostIdentityMarker)).value or "") else "";
  currentIdentity = lib.removeSuffix "\n" markerContent;
in
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
  serv.graphide.enable = true;
  serv.graphide-web.enable = true;

  # One throwaway browser IDE per name, at <name>.graphide.net behind Authelia.
  # Each is recycled hourly, which is what expires a guest link: the container
  # comes back with a fresh database, workspace and token.
  serv.graphide-demo.enable = true;
  # Lowercase because Authelia lowercases the request host before matching its
  # access_control rules, so an uppercase domain there matches nothing and
  # falls through to the default deny. URLs are case-insensitive, so
  # DemoBox1.graphide.net still reaches demobox1.
  serv.graphide-demo.sessions = [ "demobox1" "demobox2" "demobox3" ];

  # Build on this host from the repos rather than pulling a prebuilt image.
  # The other services take images from GHCR because CI publishes them; this
  # needs no Actions minutes and no registry, so it keeps working when Actions
  # is unavailable. A local tag cannot be pulled, hence autoUpdate = false.
  serv.graphide-demo.image = "localhost/graphide-demo:latest";
  serv.graphide-demo.autoUpdate = false;
  serv.graphide-demo.autoBuild.enable = true;
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
