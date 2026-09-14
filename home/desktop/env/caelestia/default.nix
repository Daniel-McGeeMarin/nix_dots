{ config, lib, pkgs, inputs, ... }:
# The personal rice. One of the two shells this host can run -- see
# ../shells.nix for the option that picks between them and the `rice` command
# that swaps them at runtime. Everything here is behind
# `desktop.shell.caelestia.enable` so that turning it off removes the build,
# not just the autostart.

let
  cfg = config.desktop.shell.caelestia;
  patched-caelestia = import ./patches {
    caelestia-shell = inputs.caelestia-shell.packages.${pkgs.stdenv.hostPlatform.system}.with-cli;
  };
in
{
  imports = [
    inputs.caelestia-shell.homeManagerModules.default
  ];

  config = lib.mkIf cfg.enable {
    programs.caelestia = {
      enable = true;
      package = patched-caelestia;
      systemd = {
        enable = true;
        target = "graphical-session.target";
        environment = [];
      };
      cli.enable = true;
    };

    # Apps launched from the caelestia launcher are spawned by the shell process,
    # so they land in caelestia.service's cgroup. systemd's default
    # KillMode=control-group then SIGKILLs every process in that cgroup whenever
    # the unit stops -- which includes every `nixos-rebuild switch`, since a new
    # shell derivation restarts the unit. That was silently killing Cursor, Orca
    # and Paseo mid-session.
    #
    # KillMode=process signals only the main quickshell process, leaving the
    # launched apps alone. Cost: helper processes the shell spawned (nmcli
    # monitor et al) are reparented to init instead of being reaped, so a few
    # megabytes leak per restart. Cheap next to losing an editor.
    systemd.user.services.caelestia.Service.KillMode = "process";

    # The session picks one shell at login (../shells.nix); neither unit may
    # start itself, or both would come up at once on the same screen.
    systemd.user.services.caelestia.Install.WantedBy = lib.mkForce [ ];

    xdg.configFile."caelestia/shell.json".source =
      config.lib.file.mkOutOfStoreSymlink
        "${config.home.homeDirectory}/nixos/home/desktop/env/caelestia/confs/shell.json";
    xdg.configFile."caelestia/shell-tokens.json".source =
      config.lib.file.mkOutOfStoreSymlink
        "${config.home.homeDirectory}/nixos/home/desktop/env/caelestia/confs/shell-tokens.json";

    home.activation.caelestiaWallpaperDir = lib.hm.dag.entryAfter ["writeBoundary"] ''
      $DRY_RUN_CMD ${pkgs.gnused}/bin/sed -i \
        "s|\"wallpaperDir\": \"/home/[^/]*/Pictures/Wallpapers\"|\"wallpaperDir\": \"${config.home.homeDirectory}/Pictures/Wallpapers\"|g" \
        "${config.home.homeDirectory}/nixos/home/desktop/env/caelestia/confs/shell.json"
    '';
  };
}
