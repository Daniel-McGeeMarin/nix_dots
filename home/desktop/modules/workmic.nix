{ pkgs, lib, config, ... }:
let
  cfg = config.desktop.workmic;

  workmic = pkgs.writeShellApplication {
    name = "workmic";
    runtimeInputs = [ pkgs.pulseaudio pkgs.libnotify pkgs.coreutils pkgs.gnugrep ];
    text = ''
      # Push-to-talk gate for the default PipeWire source.
      #
      #   workmic toggle   arm / disarm PTT mode (mic is force-muted while armed)
      #   workmic talk     key down  — unmute, but only while armed
      #   workmic release  key up    — remute
      #   workmic status   print current state

      state_dir="''${XDG_RUNTIME_DIR:-/tmp}/workmic"
      armed="$state_dir/armed"        # exists while PTT mode is on; holds pre-arm mute state
      talking="$state_dir/talking"    # exists while the key is held down
      nid_file="$state_dir/nid"       # notification id, so we only ever occupy one slot
      mkdir -p "$state_dir"

      mic_mute()   { pactl set-source-mute @DEFAULT_SOURCE@ 1; }
      mic_unmute() { pactl set-source-mute @DEFAULT_SOURCE@ 0; }
      mic_state()  { pactl get-source-mute @DEFAULT_SOURCE@ | grep -q yes && echo yes || echo no; }

      # Replace the previous workmic notification rather than stacking a new one.
      notify() { # urgency timeout title body
        local id new
        id=$(cat "$nid_file" 2>/dev/null || echo 0)
        [ -n "$id" ] || id=0
        new=$(notify-send -a workmic -p --replace-id="$id" -u "$1" -t "$2" "$3" "$4")
        printf '%s' "$new" > "$nid_file"
      }

      case "''${1:-status}" in
        toggle)
          if [ -e "$armed" ]; then
            # Disarm: put the mic back the way we found it.
            if [ "$(cat "$armed")" = yes ]; then mic_mute; else mic_unmute; fi
            rm -f "$armed" "$talking"
            if [ "$(mic_state)" = yes ]; then
              notify normal 4000 "Push-to-talk OFF" "Mic restored — still muted"
            else
              notify critical 5000 "Push-to-talk OFF" "MIC IS LIVE — nothing is gating it now"
            fi
          else
            mic_state > "$armed"
            rm -f "$talking"
            mic_mute
            notify critical 5000 "PUSH-TO-TALK ARMED" "Mic muted — hold SUPER+SPACE to talk"
          fi
          ;;

        talk)
          [ -e "$armed" ] || exit 0
          if [ -e "$talking" ]; then exit 0; fi   # key repeat / double fire
          touch "$talking"
          mic_unmute
          notify critical 0 "MIC LIVE" "Transmitting — release to mute"
          ;;

        release)
          [ -e "$armed" ] || exit 0
          rm -f "$talking"
          mic_mute
          notify low 1500 "Mic muted" "Push-to-talk still armed"
          ;;

        status)
          if [ -e "$armed" ]; then
            echo "armed, $([ -e "$talking" ] && echo talking || echo idle) (mic muted: $(mic_state))"
          else
            echo "off (mic muted: $(mic_state))"
          fi
          ;;

        *)
          echo "usage: workmic {toggle|talk|release|status}" >&2
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
