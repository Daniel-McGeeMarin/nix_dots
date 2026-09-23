{ config, lib, pkgs, inputs, ... }:
# Which desktop shell this host runs, and how to change your mind about it
# without a rebuild.
#
# There are two: caelestia (./caelestia, the personal rice) and the Graphide
# company desktop (./graphide-shell, which comes out of the monolith repo).
# Both are Quickshell shells, both draw a bar and a launcher, and both want the
# whole screen -- so exactly one may run at a time.
#
# The naive way to switch would be an option plus `nixos-rebuild`, which is a
# two-minute round trip to change a wallpaper. Instead both shells are built
# and installed, neither unit starts itself (each sets
# `Install.WantedBy = mkForce []`), and one small oneshot unit --
# rice-session.service -- starts whichever one a state file names at login.
# `rice` rewrites that state file and moves the running shell across in the
# same breath, so SUPER+CTRL+R swaps desktops in about a second.
#
#   rice                 what is running now
#   rice toggle          swap to the other one          (SUPER+CTRL+R)
#   rice use graphide    switch to a named shell
#   rice ipc launcher    open a surface on whichever shell is active
#
# `desktop.shell.default` only decides what comes up when this machine has no
# recorded choice yet; a live toggle is remembered across reboots and is not
# overridden by a rebuild. Setting either `.enable` to false drops that shell
# out of the build entirely -- that is the knob for getting the closure back,
# as opposed to the knob for choosing.
let
  cfg = config.desktop.shell;

  available = lib.optional cfg.caelestia.enable "caelestia"
    ++ lib.optional cfg.graphide.enable "graphide";

  # Caelestia's own `drawers` IPC handler, NOT `hyprctl dispatch global`.
  #
  # The global dispatcher looked like the obvious route -- it is what the
  # keybinds used before -- but it cannot work for the launcher. Caelestia
  # binds that shortcut to the key *release*, not the press
  # (modules/Shortcuts.qml: `onPressed` only clears launcherInterrupted,
  # `onReleased` does the toggle), and Hyprland's global-shortcut protocol
  # sends press/release from real key state. A `hyprctl dispatch global` is not
  # a key, so the release edge never arrives and the launcher never opens.
  # Sidebar happened to survive because it toggles on press.
  #
  # `caelestia-shell ipc call drawers toggle <drawer>` is the mechanism
  # caelestia itself exposes for this, has no press/release semantics, and
  # keeps the same fullscreen guard the shortcut had. Called directly rather
  # than through the `caelestia` Python CLI, which is a ~100ms interpreter
  # start in front of exactly this command -- too slow for a launcher key.
  #
  # Guarded on .enable so a caelestia-less build does not drag the shell into
  # the closure just to hold a path it will never run.
  # The Rofi front-end for the agent-desktop picker, used as the caelestia-mode
  # fallback for `rice ipc desktops`. It is the same backend the Graphide
  # launcher's Desktops tab drives -- both end in `agent-desktops open <id>` --
  # so SUPER+A means the same thing in either shell, it just looks different.
  #
  # This has to be installed explicitly. The path the keybind used before
  # (agent-config/.../view-agent-desktops.sh) stopped being an implementation
  # some time ago; it is now a shim that execs `view-agent-desktops-rofi` and
  # exits 127 with "Missing view-agent-desktops-rofi" when that is not on PATH,
  # which is exactly what SUPER+A had been doing on this machine. The real
  # thing lives in the Graphide flake.
  viewAgentDesktops = inputs.graphide-tools.packages.${pkgs.stdenv.hostPlatform.system}.view-agent-desktops;

  caelestiaDrawer =
    if cfg.caelestia.enable
    then "${config.programs.caelestia.package}/bin/caelestia-shell ipc call drawers toggle"
    else "true";

  rice = pkgs.writeShellApplication {
    name = "rice";
    runtimeInputs = [ pkgs.systemd pkgs.libnotify pkgs.coreutils ];
    text = ''
      AVAILABLE="${lib.concatStringsSep " " available}"
      DEFAULT="${cfg.default}"
      STATE_DIR="''${XDG_STATE_HOME:-$HOME/.local/state}/rice"
      STATE="$STATE_DIR/active"

      # The names above are what you type; these are what systemd calls them.
      unit_of() {
        case "$1" in
          caelestia) echo caelestia ;;
          graphide)  echo graphide-shell ;;
          *)         return 1 ;;
        esac
      }

      known() {
        case " $AVAILABLE " in
          *" $1 "*) return 0 ;;
          *)        return 1 ;;
        esac
      }

      # The recorded shell, falling back to the configured default when the
      # state file is missing or names something this build does not have --
      # which is the first boot, and any boot after an `.enable` was flipped
      # off while the state file still pointed at it.
      active() {
        if [ -r "$STATE" ]; then
          recorded="$(cat "$STATE")"
          if known "$recorded"; then
            echo "$recorded"
            return 0
          fi
        fi
        echo "$DEFAULT"
      }

      other() {
        # shellcheck disable=SC2086 # AVAILABLE is a deliberate word list
        for s in $AVAILABLE; do
          if [ "$s" != "$1" ]; then
            echo "$s"
            return 0
          fi
        done
        echo "$1"
      }

      note() { notify-send -a rice -u low "$1" "$2" 2>/dev/null || true; }

      # Stop every shell we know of, not only the recorded one: if something
      # started a second by hand, a switch has to land on an empty screen or
      # the two draw over each other.
      stop_all() {
        # shellcheck disable=SC2086
        for s in $AVAILABLE; do
          systemctl --user stop "$(unit_of "$s").service" 2>/dev/null || true
        done
      }

      start() {
        # --no-block: `rice apply` runs from inside rice-session.service, and a
        # blocking start of another unit in the same transaction is how that
        # becomes a hang instead of a desktop.
        systemctl --user start --no-block "$(unit_of "$1").service"
      }

      cmd="''${1:-status}"
      case "$cmd" in
        status)
          printf '%s   (available: %s, default: %s)\n' "$(active)" "$AVAILABLE" "$DEFAULT"
          ;;

        list)
          # shellcheck disable=SC2086
          for s in $AVAILABLE; do echo "$s"; done
          ;;

        # Start whatever the state file names. This is the login path.
        apply)
          want="$(active)"
          stop_all
          start "$want"
          ;;

        stop)
          stop_all
          ;;

        use)
          want="''${2:-}"
          if ! known "$want"; then
            echo "rice: unknown shell '$want' (have: $AVAILABLE)" >&2
            exit 1
          fi
          mkdir -p "$STATE_DIR"
          echo "$want" > "$STATE"
          stop_all
          start "$want"
          note "Desktop shell" "$want"
          ;;

        toggle)
          if [ "$(echo "$AVAILABLE" | wc -w)" -lt 2 ]; then
            echo "rice: only one shell is built ($AVAILABLE); nothing to toggle" >&2
            exit 1
          fi
          exec "$0" use "$(other "$(active)")"
          ;;

        # Open a surface on whichever shell is up. Both shells answer on
        # Quickshell IPC, but on different targets with different verbs
        # (caelestia: drawers/toggle, Graphide: desktop/<surface>), so the
        # keybinds go through here rather than calling either one directly.
        ipc)
          surface="''${2:-launcher}"
          case "$(active)" in
            caelestia)
              case "$surface" in
                launcher) ${caelestiaDrawer} launcher ;;
                sidebar)  ${caelestiaDrawer} sidebar ;;
                desktops) ${viewAgentDesktops}/bin/view-agent-desktops-rofi ;;
                *)        note "rice" "no '$surface' in caelestia" ;;
              esac
              ;;
            graphide)
              case "$surface" in
                launcher)         graphide-shell ipc call desktop apps ;;
                sidebar|accounts) graphide-shell ipc call desktop accounts ;;
                vault)            graphide-shell ipc call desktop vault ;;
                desktops)         graphide-shell ipc call desktop desktops ;;
                bar)              graphide-shell ipc call desktop toggleBar ;;
                widgets)          graphide-shell ipc call desktop toggleWidgets ;;
                *)                note "rice" "no '$surface' in the Graphide shell" ;;
              esac
              ;;
          esac
          ;;

        *)
          echo "usage: rice [status|list|toggle|use <shell>|apply|stop|ipc <surface>]" >&2
          exit 1
          ;;
      esac
    '';
  };
in
{
  options.desktop.shell = {
    default = lib.mkOption {
      type = lib.types.enum [ "caelestia" "graphide" ];
      default = "caelestia";
      description = ''
        Shell brought up when this machine has no recorded choice yet. A live
        `rice use` is remembered in XDG state and wins over this afterwards.
      '';
    };

    caelestia.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Build and install the caelestia shell.";
    };

    graphide = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Build and install the Graphide company shell.";
      };

      widgetMonitor = lib.mkOption {
        type = lib.types.str;
        default = "";
        example = "eDP-1";
        description = ''
          Monitor carrying the permanent company widgets. Empty, or a name
          that is not connected, falls back to the first connected screen.
        '';
      };

      reserveWidgetSpace = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Make the company widgets a reserved sidebar that tiled windows
          shrink around, rather than decoration sitting at wallpaper level
          behind them.
        '';
      };

      decoration = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Let the Graphide shell force the gaps, rounding and border size it
          was drawn against. Off because it is `mkForce` over the whole
          compositor, so it would follow you back into caelestia.
        '';
      };

      rbwPinentry = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Route rbw's pinentry through the shell's inline unlock helper. Off
          because it is `mkForce` over `programs.rbw.settings.pinentry` for
          every rbw invocation, not just the shell's vault tab -- including
          the ones that happen while the Graphide shell is not running.
        '';
      };
    };
  };

  config = {
    assertions = [{
      assertion = available != [ ];
      message = "desktop.shell: both shells are disabled, so the session would have no bar and no launcher at all. Enable at least one of desktop.shell.caelestia.enable / desktop.shell.graphide.enable.";
    }];

    home.packages = [ rice viewAgentDesktops ];

    # The login path. Neither shell unit is wanted by graphical-session.target
    # on its own (see the mkForce in each module), so this is the only thing
    # that ever starts one -- which is what keeps "exactly one at a time" true
    # across a reboot as well as across a toggle. No ExecStop: both shells are
    # PartOf graphical-session.target already, so they go down with the
    # session, and stopping them from this unit's own shutdown would be a
    # second job in the same transaction.
    systemd.user.services.rice-session = {
      Unit = {
        Description = "Start the desktop shell selected by `rice`";
        After = [ "graphical-session.target" ];
        PartOf = [ "graphical-session.target" ];
        ConditionEnvironment = "WAYLAND_DISPLAY";
      };
      Service = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "${rice}/bin/rice apply";
      };
      Install.WantedBy = [ "graphical-session.target" ];
    };
  };
}
