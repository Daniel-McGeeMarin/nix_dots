{ config, lib, options, pkgs, inputs, ... }:
# The Graphide company desktop: bar, launcher, wallpaper and company widgets,
# drawn in Quickshell. It is the second of the two shells this host can run --
# see ../shells.nix for the option that picks between them and the `rice`
# command that swaps them at runtime.
#
# The module itself lives in the monolith repo (nix/home-manager/quickshell.nix)
# and reaches us through the `graphide-tools` flake input, which follows master
# rather than a release: the shell is pure QML with no tie to CI's tarball, so
# waiting for a release would only delay rice changes. Importing it costs nothing
# on its own: every knob that would impose something on the rest of this
# configuration defaults off upstream.
let
  cfg = config.desktop.shell.graphide;
in
{
  imports = [
    inputs.graphide-tools.homeManagerModules.quickshell
  ];

  config = lib.mkIf cfg.enable (lib.mkMerge [ {
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

      # Clicking the panel's TODO section (or its OPEN button) edits the shared
      # list. The window it opens is titled TODO, which is what the
      # `### TODO scratchpad ###` rules in ../hyprland/rules.nix already match:
      # float, 600x800, centred and pinned. The board keeps showing the
      # *committed* copy from GitHub, so an edit appears on the panel once it
      # is pushed, not when it is saved.
      todoCommand = [ "nvim" "${config.home.homeDirectory}/Documents/startup/Graphide/docs/TODO.md" ];
      # The company panel's COMMITS section: Dan's and Ben's commits per day and
      # the net lines master gained, from this checkout's origin/master (fetched
      # hourly into the remote-tracking ref; the working tree is never touched).
      commitsRepo = "${config.home.homeDirectory}/Documents/startup/Graphide/monolith";
      # The bar's Wi-Fi item opens the Wi-Fi manager (../../apps/wlctl.nix).
      wifiCommand = [ "wifi" ];

      # The reminders column down the right edge: Dan's shared list on
      # XiaServer (http://xiaserver:8422/dan.json), which Ben can add to from
      # his shell. The launcher's Remind place adds to Dan's or Ben's. Done is
      # sent over ssh as reminders@xiaserver, which takes Dan's human key.
      serverReminders = {
        person = "dan";
        addTo = [ "dan" "ben" ];
      };

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
    # the other way. The launcher opens on a key and must be there at once: its
    # slide from the top ran at the global speed (~0.8 s), so it gets none.
    wayland.windowManager.hyprland.settings.layerrule = [
      "animation fade, ^(graphide-.*)$"
      "noanim, ^(graphide-launcher)$"
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
  }
  # Upstream's to-do column turns light, blinks now and then and grows a
  # quarter of the screen over a working day by default -- a nudge meant for
  # Ben's desktop, not this one. Guarded on the option existing, so it holds
  # across a graphide-tools pin from before the option and after it.
  (lib.optionalAttrs (options.programs.graphide-shell ? todoColumn) {
    programs.graphide-shell.todoColumn = {
      theme = "dark";
      blink = false;
      grow.share = 0;
    };
  })
  # The customer board down the right edge: every company with a person
  # tagged `customer` in the outreach brain, by where the ball is, fetched every
  # minute with ~/.config/outreach-brain/config.toml. Same guard as above.
  (lib.optionalAttrs (options.programs.graphide-shell ? customers) {
    programs.graphide-shell.customers.enable = true;
  })
  # One sidebar down the right edge in place of the reminders column and the
  # customer board: tabs for Dan's own live reminders, Ben's reminders, the
  # customers and any page an agent writes with `graphide-sidebar`, all
  # changed live from ~/.config/graphide-shell/sidebar. Off upstream, so Ben's
  # desktop keeps the column. Same guard as above.
  (lib.optionalAttrs (options.programs.graphide-shell ? sidebar) {
    programs.graphide-shell.sidebar.enable = true;
  })
  # The brain dashboard in that sidebar: Important (mail owed an answer, with a
  # red count), Customers, CI/CD, PR bot and Contacts, rewritten every two
  # minutes from the outreach brain and grail's triage. Off upstream. Guarded
  # on the option existing, like the rest.
  (lib.optionalAttrs (options.programs.graphide-shell ? sidebar
      && options.programs.graphide-shell.sidebar ? dashboard) {
    programs.graphide-shell.sidebar.dashboard.enable = true;
  })
  # The reminders column, by contrast, should nag here: while a reminder is
  # owed it widens a step every half hour until, 12 hours after it first
  # showed, it covers 60% of the screen. Half-hour steps are about 30 px each;
  # upstream's 10-minute default would be 10 px slivers that re-tile every
  # window for nothing you can see. Snoozing hides it but does not shrink it.
  # The sidebar grows the same way. Off upstream, so Ben's desktop is
  # untouched. Same guard as above.
  (lib.optionalAttrs (options.programs.graphide-shell ? remindersColumn) {
    programs.graphide-shell.remindersColumn.grow = {
      widest = 0.6;
      minutes = 720;
      stepMinutes = 30;
    };
  })
  ]);
}
