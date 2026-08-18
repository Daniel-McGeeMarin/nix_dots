{ pkgs, lib, config, ... }:
let
  cfg = config.desktop.workmic;

  workmic = pkgs.writeShellApplication {
    name = "workmic";
    runtimeInputs = [ pkgs.pulseaudio pkgs.libnotify pkgs.coreutils pkgs.gawk pkgs.procps ];
    text = ''
      # Push-to-talk gate for microphone capture.
      #
      #   workmic toggle   arm / disarm PTT mode (capture stays muted while armed)
      #   workmic talk     key down  — unmute, but only while armed
      #   workmic release  key up    — remute
      #   workmic status   print current state
      #   workmic reset    unmute everything (clears a stuck stream-restore mute)
      #   workmic watch    internal: mute capture streams that appear while armed
      #
      # This gates each application's *capture stream* (pulse source-output), never
      # the source device itself. Muting the device emits a PA source-change event;
      # Signal's RingRTC uses cubeb's pulse backend, which reacts to those by tearing
      # down and re-initialising its recording stream — every press and release, which
      # is enough to kill a live call. Stream mutes only emit source-output events,
      # which cubeb does not subscribe to.

      state_dir="''${XDG_RUNTIME_DIR:-/tmp}/workmic"
      armed="$state_dir/armed"        # exists while PTT mode is on; holds pre-arm per-app mute state
      talking="$state_dir/talking"    # exists while the key is held down
      nid_file="$state_dir/nid"       # notification id, so we only ever occupy one slot
      watch_pid="$state_dir/watch.pid"
      mkdir -p "$state_dir"

      # "<id> <app.name> <yes|no>" per active capture stream
      capture_streams() {
        pactl list source-outputs | awk '
          /^Source Output #/ { id = substr($3, 2); app = "?"; mute = "no" }
          /^\tMute:/         { mute = $2 }
          /application\.name = / { gsub(/"/, "", $3); app = $3 }
          /^$/ { if (id != "") { print id, app, mute; id = "" } }
          END  { if (id != "") print id, app, mute }
        '
      }

      set_all() { # 1 = mute, 0 = unmute
        while read -r id _ _; do
          [ -n "$id" ] || continue
          pactl set-source-output-mute "$id" "$1" 2>/dev/null || true
        done < <(capture_streams)
      }

      # Replace the previous workmic notification rather than stacking a new one.
      notify() { # urgency timeout title body
        local id new
        id=$(cat "$nid_file" 2>/dev/null || echo 0)
        [ -n "$id" ] || id=0
        new=$(notify-send -a workmic -p --replace-id="$id" -u "$1" -t "$2" "$3" "$4")
        printf '%s' "$new" > "$nid_file"
      }

      stop_watcher() {
        if [ -e "$watch_pid" ]; then
          local pid
          pid=$(cat "$watch_pid")
          kill -- -"$pid" 2>/dev/null || kill "$pid" 2>/dev/null || true
          rm -f "$watch_pid"
        fi
      }

      case "''${1:-status}" in
        toggle)
          if [ -e "$armed" ]; then
            stop_watcher
            # Unmute everything except apps the user already had muted before arming.
            while read -r id app _; do
              [ -n "$id" ] || continue
              if grep -qx "$app yes" "$armed" 2>/dev/null; then continue; fi
              pactl set-source-output-mute "$id" 0 2>/dev/null || true
            done < <(capture_streams)
            rm -f "$armed" "$talking"
            notify critical 5000 "Push-to-talk OFF" "MIC IS LIVE — nothing is gating it now"
          else
            capture_streams | awk '{print $2, $3}' > "$armed"
            rm -f "$talking"
            set_all 1
            rm -f "$watch_pid"
            setsid "$0" watch >/dev/null 2>&1 &
            notify critical 5000 "PUSH-TO-TALK ARMED" "Mic muted — hold SUPER+SPACE to talk"
          fi
          ;;

        talk)
          [ -e "$armed" ] || exit 0
          if [ -e "$talking" ]; then exit 0; fi   # key repeat / double fire
          touch "$talking"
          set_all 0
          notify critical 0 "MIC LIVE" "Transmitting — release to mute"
          ;;

        release)
          [ -e "$armed" ] || exit 0
          rm -f "$talking"
          set_all 1
          notify low 1500 "Mic muted" "Push-to-talk still armed"
          ;;

        watch)
          # An app that starts capturing while armed would otherwise come up hot —
          # e.g. joining a call after arming, or RingRTC rebuilding its stream.
          # Only 'new' events: our own mutes emit 'change', which would feed back.
          echo $$ > "$watch_pid"
          pactl subscribe 2>/dev/null | while read -r line; do
            [ -e "$armed" ] || exit 0
            case "$line" in
              *"'new' on source-output"*)
                if [ -e "$talking" ]; then continue; fi
                set_all 1
                ;;
            esac
          done
          ;;

        reset)
          # Escape hatch: pulse's stream-restore remembers mute per application name,
          # so dying while armed can leave an app muted on its next launch. Run this
          # with the affected app capturing to clear it.
          stop_watcher
          rm -f "$armed" "$talking"
          set_all 0
          notify normal 3000 "Push-to-talk reset" "All capture streams unmuted"
          ;;

        status)
          if [ -e "$armed" ]; then
            echo "armed, $([ -e "$talking" ] && echo talking || echo idle)"
          else
            echo "off"
          fi
          capture_streams | awk '{print "  stream #" $1 " " $2 " muted=" $3}'
          ;;

        *)
          echo "usage: workmic {toggle|talk|release|status|reset}" >&2
          exit 1
          ;;
      esac
    '';
  };
in
{
  options.desktop.workmic = {
    enable = lib.mkEnableOption "Push-to-talk mic gating";

    mod = lib.mkOption {
      type = lib.types.str;
      default = "SUPER";
      description = "Modifier for the push-to-talk key. SHIFT is added for the arm/disarm toggle.";
    };

    key = lib.mkOption {
      type = lib.types.str;
      default = "SPACE";
      description = "Key held to transmit.";
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [ workmic ];

    wayland.windowManager.hyprland.settings = {
      # bindl/bindrl: keep working when the session is locked or the screen is off.
      bindl = [
        "${cfg.mod} SHIFT, ${cfg.key}, exec, ${workmic}/bin/workmic toggle"
        "${cfg.mod}, ${cfg.key}, exec, ${workmic}/bin/workmic talk"
      ];
      bindrl = [
        "${cfg.mod}, ${cfg.key}, exec, ${workmic}/bin/workmic release"
      ];
    };
  };
}
