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
    # No ../../system/head: that omission is what makes this box headless.
    # system/headless is its counterpart -- sshd, the trusted tailnet interface
    # and the never-sleep targets. It is imported separately from serv/ on
    # purpose: those things must survive `serv.enable = false`.
    ../../system/headless
    ../../system/podman.nix
    ../../system/serv
    ../../system/graphide
    inputs.agenix.nixosModules.default
    ./hardware-configuration.nix
    ./storage.nix
    ./tv-seat.nix
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

  # Server with a minimal TV seat: note the absence of ../../system/head in the
  # imports above. tv-seat.nix adds only greetd, labwc, on-demand XWayland,
  # basic audio and a font. There is still no GDM, GNOME, Hyprland, Plymouth or
  # gamescope. The machine remains administered through the headless module.

  # The whole mcgeedan.com estate, off in one line: blogs, dashboard, forge,
  # cloud storage, office, the personal site and the finance app. Their
  # containers, their Caddy, their tunnel and the OCIS firewall hole all go with
  # it. Set this back to true to bring the lot back exactly as it was - nothing
  # about those modules changed, they are simply not enabled.
  #
  # This is safe to flip because sshd, the trusted tailnet interface and podman
  # no longer live under it; see system/headless and system/podman.nix.
  serv.enable = false;

  # The one exception, and the last thread tying the two stacks together.
  # Graphide's admin pages authenticate against the Authelia instance declared
  # in system/serv/auth.nix, so it stays up on its own. Demo boxes do not use
  # it — they are behind the magic-link gate in system/graphide/gate.nix.
  # Authelia binds 0.0.0.0:9091 and Graphide's own Caddy proxies
  # auth.graphide.net to it. See the header of system/graphide/auth.nix.
  serv.auth.enable = true;

  # The Graphide stack: API, marketing site and demo boxes. Its own tree, its
  # own tunnel, its own Caddy, its own switch. Deliberately not covered by
  # serv.enable above -- this must stay up when the estate goes down.
  graphide.enable = true;

  # The API server is not ready to deploy, so it stays off: no postgres, no
  # redis, no monolith-api container, and no api.graphide.net route. Nothing
  # else needs it -- each demo pod runs its own postgres, redis and API inside
  # the container, and website-api talks to Supabase.
  graphide.api.enable = false;

  # Build the website here too, for the reason the demo pods already do it
  # below. The GHCR path failed in the way that comment predicted: Actions
  # minutes ran out, CI stopped publishing, and the box sat on `manifest
  # unknown` for website-api while graphide.net quietly served a build from
  # 4 August. Nothing was broken except the thing nobody was watching.
  #
  # The borrowed clone token is graphide-demo's PAT, which must include the
  # website repo in its scope.
  graphide.web.image = "localhost/website:latest";
  graphide.web.apiImage = "localhost/website-api:latest";
  graphide.web.autoUpdate = false;
  graphide.web.autoBuild.enable = true;

  # One throwaway browser IDE per name, at <name>.graphide.net behind the
  # magic-link gate. Mint a link on the box with:
  #   graphide-demo-mint --box demobox1 --ttl 12h --label "press"
  graphide.demo.enable = true;
  # Lowercase: the hostname is the Authelia/Caddy/token `box` id. URLs are
  # case-insensitive, so DemoBox1.graphide.net still reaches demobox1.
  graphide.demo.sessions = [ "demobox1" "demobox2" "demobox3" ];

  # Build on this host from the repos rather than pulling a prebuilt image.
  # The other services take images from GHCR because CI publishes them; this
  # needs no Actions minutes and no registry, so it keeps working when Actions
  # is unavailable. A local tag cannot be pulled, hence autoUpdate = false.
  graphide.demo.image = "localhost/graphide-demo:latest";
  graphide.demo.autoUpdate = false;
  graphide.demo.autoBuild.enable = true;

  # All three boxes run the patched editor.
  #
  # The two images differ in exactly one thing - which VSCodium server they
  # carry - and only the patched one has the Graphide title bar, the
  # Home/File/Edit/Advanced menu bar, full-window page mode and the
  # reserved-canvas guarantees. Everything else, including the extension, is
  # identical.
  #
  # Moving a box back to stock is deleting its `imageFor` line and letting it
  # take the default. Do NOT instead point `image` at the fork tag: the
  # autobuild promotes the STOCK build into `image`, so that would overwrite
  # the fork tag on every cycle.
  #
  # Note what is given up here. A cycle where the patched server is stale or
  # absent skips the fork pod build and promotes only stock, so with no box on
  # the default there is no longer one that keeps updating when the fork half
  # is stuck.
  graphide.demo.autoBuild.buildFork = true;
  graphide.demo.imageFor.demobox1 = "localhost/graphide-demo:fork";
  graphide.demo.imageFor.demobox2 = "localhost/graphide-demo:fork";
  graphide.demo.imageFor.demobox3 = "localhost/graphide-demo:fork";

  # Keep what guests do, and open a real project rather than an empty folder.
  # This is a deliberate trade: the hourly wipe was what expired a guest's
  # access to their own session, so with it off, whatever one visitor leaves in
  # a workspace is what the next one opens.
  graphide.demo.persist = true;
  graphide.demo.recycle.enable = false;
  graphide.demo.seedDir = "/srv/graphide/demo/seed";
  services.openssh.settings.PasswordAuthentication = false;

  # NVIDIA 1080 Ti — standalone GPU, no PRIME. The card is physically in the
  # box, so the kernel driver is built and nvidia-smi works, but nothing on this
  # host consumes it today. Kept so a GPU workload can be added later without
  # touching hardware config.
  #
  # services.xserver.videoDrivers is what makes NixOS build the nvidia module at
  # all — the whole hardware.nvidia module is gated on this list. It does NOT
  # start an X server; that is services.xserver.enable, which is off.
  services.xserver.videoDrivers = [ "nvidia" ];
  hardware.graphics.enable = true;
  hardware.nvidia = {
    modesetting.enable = true;
    powerManagement.enable = false;
    open = false;
    # Keep the control panel out of the minimal TV environment.
    nvidiaSettings = false;
    package = config.boot.kernelPackages.nvidiaPackages.stable;
  };

  # cudatoolkit and cuda_cudart used to sit here. Between them they are several
  # gigabytes, and nothing on this host links against CUDA — there is no local
  # model server and no GPU job runner. Put them back next to whatever needs them.
  environment.systemPackages = [
    inputs.agenix.packages.x86_64-linux.default
  ];

  programs = {
    # A dynamic loader at the path non-Nix binaries expect, so a downloaded
    # toolchain runs without patchelf. Costs nothing and stays.
    nix-ld.enable = true;
    nix-ld.libraries = [ ];

    # system/default.nix picks the GTK pinentry, which has no display to draw on
    # here — gpg would hang waiting for a window that never appears. Curses
    # prompts in the SSH terminal instead.
    gnupg.agent.pinentryPackage = lib.mkForce pkgs.pinentry-curses;
  };

  # tv-seat.nix supplies one small fallback font family for GUI applications.

  time.timeZone = "America/Los_Angeles";

  users.users.XiaServer = {
    isNormalUser = true;
    shell = pkgs.zsh;
    # greetd/logind grants the active local session device ACLs. SSH-launched
    # applications only connect to labwc's socket, so broad video/input group
    # membership is unnecessary.
    extraGroups = [ "wheel" ];
  };

  home-manager = {
    backupFileExtension = "backup";
    extraSpecialArgs = { flakeAttr = "XiaServer"; };
    users."XiaServer" = import ./home.nix;
  };

  nix.package = pkgs.lix;

  system.stateVersion = "24.11";
}
