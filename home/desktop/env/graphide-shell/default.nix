{ config, lib, pkgs, inputs, ... }:
# The Graphide company desktop: bar, launcher, wallpaper and company widgets,
# drawn in Quickshell. It is the second of the two shells this host can run --
# see ../shells.nix for the option that picks between them and the `rice`
# command that swaps them at runtime.
#
# The module itself lives in the monolith repo (nix/home-manager/quickshell.nix)
# and reaches us through the `graphide` flake input, the same input that already
# supplies gr/grat. Importing it costs nothing on its own: every knob that would
# impose something on the rest of this configuration defaults off upstream.
let
  cfg = config.desktop.shell.graphide;
in
{
  imports = [
    inputs.graphide.homeManagerModules.quickshell
  ];

  config = lib.mkIf cfg.enable {
    programs.graphide-shell = {
      enable = true;

      # NOT pkgs.quickshell. nixpkgs 25.11 carries Quickshell 0.2.1, and the
      # QML in the monolith is written against 0.3 (its own README links the
      # v0.3.0 type reference). unstable has 0.3.1. Caelestia sidesteps this by
      # vendoring Quickshell in its own flake input; pointing at unstable is
      # cheaper than adding a third copy of the same toolkit to the closure.
      package = pkgs.unstable.quickshell;

      # The shell shells out to a terminal for vendor logins and connector
      # setup. Pin the package rather than trusting PATH, so it works even
      # when the unit is started outside a login shell.
      terminal = "kitty";
      terminalPackage = pkgs.kitty;

      # waybar-module-pomodoro is not in nixpkgs (it is
      # github:Andeskjerf/waybar-module-pomodoro). Null hides the widget and
      # never starts the process.
      pomodoro = null;

      inherit (cfg) widgetMonitor reserveWidgetSpace rbwPinentry;

      hyprland = {
        # OFF, and the rules are written by hand below instead. Upstream emits
        # Hyprland's newer `match:namespace ^(...)$` rule syntax; the Hyprland
        # in nixpkgs 25.11 is 0.52.2, which rejects it outright --
        # `hyprctl keyword layerrule 'match:namespace ^(graphide-.*)$, animation
        # fade'` answers "Invalid rule found". Leaving it on would put two rules
        # in hyprland.conf that this compositor refuses, and no animation.
        layerRules = false;
        # mkForces gaps/rounding/border for the whole compositor, which then
        # follows into caelestia mode too -- hence an option, defaulted off.
        decoration = cfg.decoration;
      };
    };

    # The 0.52 spelling of what layerRules would have written. Namespace-scoped
    # to graphide-*, so caelestia's own layers are untouched when the toggle is
    # the other way. Order matters: the launcher rule has to come second to win.
    wayland.windowManager.hyprland.settings.layerrule = [
      "animation fade, ^(graphide-.*)$"
      "animation slide top, ^(graphide-launcher)$"
    ];

    # Same problem caelestia has, same fix: applications launched from the
    # shell's launcher are children of the shell process and land in this
    # unit's cgroup, so systemd's default KillMode=control-group SIGKILLs them
    # every time the unit stops -- which includes every rebuild and every
    # `rice` toggle. KillMode=process signals only the shell itself. See
    # ../caelestia/default.nix for the incident this is copied from.
    systemd.user.services.graphide-shell.Service.KillMode = "process";

    # The session picks one shell at login (../shells.nix); neither unit may
    # start itself, or both would come up at once on the same screen.
    systemd.user.services.graphide-shell.Install.WantedBy = lib.mkForce [ ];
  };
}
