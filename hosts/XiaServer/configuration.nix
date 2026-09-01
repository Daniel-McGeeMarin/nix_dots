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

  # Headless: note the absence of ../../system/head in the imports above. That
  # is the entire mechanism - no GDM, no Plymouth, no PipeWire, no gamescope,
  # because none of it is in the module set. The serv.* options below are the
  # whole machine now.

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
  # Graphide's admin pages and demo pods authenticate against the Authelia
  # instance declared in system/serv/auth.nix, so it stays up on its own.
  # Authelia binds 0.0.0.0:9091 and Graphide's own Caddy proxies
  # auth.graphide.net to it, so none of the rest of the estate is needed for
  # this to work. See the header of system/graphide/auth.nix.
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

  # One throwaway browser IDE per name, at <name>.graphide.net behind Authelia.
  # Each is recycled hourly, which is what expires a guest link: the container
  # comes back with a fresh database, workspace and token.
  graphide.demo.enable = true;
  # Lowercase because Authelia lowercases the request host before matching its
  # access_control rules, so an uppercase domain there matches nothing and
  # falls through to the default deny. URLs are case-insensitive, so
  # DemoBox1.graphide.net still reaches demobox1.
  graphide.demo.sessions = [ "demobox1" "demobox2" "demobox3" ];

  # Build on this host from the repos rather than pulling a prebuilt image.
  # The other services take images from GHCR because CI publishes them; this
  # needs no Actions minutes and no registry, so it keeps working when Actions
  # is unavailable. A local tag cannot be pulled, hence autoUpdate = false.
  graphide.demo.image = "localhost/graphide-demo:latest";
  graphide.demo.autoUpdate = false;
  graphide.demo.autoBuild.enable = true;

  # demobox1 runs the patched editor; 2 and 3 stay on the stock browser server.
  #
  # The two images differ in exactly one thing - which VSCodium server they
  # carry - and only the patched one has the Graphide title bar, the
  # Home/File/Edit/Advanced menu bar, full-window page mode and the
  # reserved-canvas guarantees. Everything else, including the extension, is
  # identical, so this is a clean A/B rather than two products.
  #
  # Both tags are built and promoted on every autobuild cycle, so moving the
  # other two over later is deleting the `imageFor` line and letting them take
  # the default - or, if the patched one is to become the default everywhere,
  # pointing `image` at it. Neither is a rebuild.
  graphide.demo.autoBuild.buildFork = true;
  graphide.demo.imageFor.demobox1 = "localhost/graphide-demo:fork";

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
    # nvidia-settings is a GUI control panel. Nothing here can display it.
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

  # No font packages: nothing on this host renders text. The containers that do
  # (OnlyOffice, the demo pods' browser server) carry their own fonts in-image.

  time.timeZone = "America/Los_Angeles";

  users.users.XiaServer = {
    isNormalUser = true;
    shell = pkgs.zsh;
    # video/input were for a graphical seat that no longer exists.
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
