{ config, lib, pkgs, ... }:
let
  user = "XiaServer";
  # Literal form of what used to be `${graphide.demo.autoBuild.srcDir}` —
  # the demo module retired to Azure 2026-09-10 and its options with it.
  monolith = "${config.graphide.dataDir}/demo/src/monolith";

  startTvSeat = pkgs.writeShellScript "start-tv-seat" ''
    export NIXOS_OZONE_WL=1
    export MOZ_ENABLE_WAYLAND=1
    export WLR_NO_HARDWARE_CURSORS=1
    export GRAPHIDE_MONOLITH=${monolith}

    # greetd starts this from a VT, so its session is XDG_SESSION_TYPE=tty and
    # nothing further along corrects that. It matters because NIXOS_OZONE_WL
    # makes the chromium wrapper pass --ozone-platform-hint=auto, and "auto"
    # decides by reading XDG_SESSION_TYPE: seeing "tty" it picks X11, fails
    # with "Missing X server or $DISPLAY", and the board never draws. Saying
    # what this session is fixes the browser without hard-coding a platform
    # flag into every client. XDG_CURRENT_DESKTOP is set for the same reason,
    # one level up: portals and toolkits branch on it and it is otherwise
    # empty here.
    export XDG_SESSION_TYPE=wayland
    export XDG_CURRENT_DESKTOP=labwc
    # greetd exec's this straight from a VT, so labwc's stdout and stderr went
    # to the tty and nowhere else: every wlroots message about this screen --
    # "connector HDMI-A-2 disconnected", failed atomic commits, mode set
    # failures -- was discarded. That is the one component best placed to say
    # why the TV went dark, so put it in the journal: `journalctl -t labwc`.
    exec ${pkgs.systemd}/bin/systemd-cat --identifier=labwc \
      ${pkgs.dbus}/bin/dbus-run-session -- ${pkgs.labwc}/bin/labwc
  '';

  # The TV drops off at random and never comes back on its own. It did that
  # when this host was headless too, long before there was a compositor to
  # blame, and the TV shows "No Signal" rather than a black picture -- so the
  # sink or the link is dropping, not anything in software. Nothing here can
  # fix a marginal HDMI link; what it can do is notice and recover.
  #
  # wlroots destroys the wlr_output when a connector reports disconnected
  # (disconnect_drm_connector() calls wlr_output_destroy outright) and relies
  # on a udev change event to bring it back. labwc 0.9.2 does not always
  # re-enable it when that arrives -- labwc#3234, open, filed against this
  # exact version and describing this exact symptom. Then the screen stays
  # dead until someone restarts the session by hand.
  #
  # So: watch the connector, and if the TV comes back but the compositor does
  # not take the output, restart the seat. Every transition is logged whether
  # or not it needed acting on, because a record of when this happens is worth
  # as much as the recovery.
  tvOutputWatch = pkgs.writeShellApplication {
    name = "tv-output-watch";
    runtimeInputs = [ pkgs.coreutils pkgs.systemd ];
    text = ''
      # Not a fixed card2-HDMI-A-2: the card index depends on whether i915 or
      # nvidia probed first and is not guaranteed across boots. The connector
      # suffix is.
      connector() {
        for c in /sys/class/drm/*-HDMI-A-2; do
          if [ -e "$c/status" ]; then
            printf '%s' "$c"
            return 0
          fi
        done
        return 1
      }

      state() {
        printf '%s enabled=%s dpms=%s edid=%s bytes' \
          "$(cat "$1/status" 2>/dev/null || echo gone)" \
          "$(cat "$1/enabled" 2>/dev/null || echo gone)" \
          "$(cat "$1/dpms" 2>/dev/null || echo gone)" \
          "$(wc -c < "$1/edid" 2>/dev/null || echo 0)"
      }

      prev=""
      while true; do
        if ! c=$(connector); then
          sleep 5
          continue
        fi

        status=$(cat "$c/status" 2>/dev/null || echo gone)

        if [ "$status" != "$prev" ]; then
          if [ -z "$prev" ]; then
            echo "watching ''${c##*/}: $(state "$c")"
          else
            echo "''${c##*/}: $prev -> $(state "$c")"
          fi

          if [ "$prev" = "disconnected" ] && [ "$status" = "connected" ]; then
            # Give labwc its chance first. When it does handle the hotplug the
            # connector goes back to enabled on its own and there is nothing to
            # do -- restarting the seat then would be a self-inflicted outage.
            sleep 10
            enabled=$(cat "$c/enabled" 2>/dev/null || echo gone)
            if [ "$enabled" = "enabled" ]; then
              echo "TV is back and the compositor re-enabled the output"
            else
              echo "TV is back but the output is still $enabled; restarting the seat"
              systemctl restart greetd
            fi
          fi

          prev="$status"
        fi

        sleep 5
      done
    '';
  };

  session = {
    user = user;
    command = toString startTvSeat;
  };

  tvRun = pkgs.writeShellApplication {
    name = "tv-run";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.findutils
      pkgs.gnugrep
      pkgs.systemd
      pkgs.wayland-utils
    ];
    text = ''
      if [ "$#" -eq 0 ]; then
        echo "usage: tv-run <program> [args...]" >&2
        exit 2
      fi

      runtime_dir="/run/user/$(id -u)"
      export XDG_RUNTIME_DIR="$runtime_dir"
      export DBUS_SESSION_BUS_ADDRESS="unix:path=$runtime_dir/bus"

      while IFS='=' read -r key value; do
        case "$key" in
          DISPLAY|NIXOS_OZONE_WL|MOZ_ENABLE_WAYLAND|GRAPHIDE_MONOLITH \
          |XDG_SESSION_TYPE|XDG_CURRENT_DESKTOP)
            export "$key=$value"
            ;;
        esac
      done < <(systemctl --user show-environment)

      # Pick the compositor that actually drives the TV, not merely the first
      # socket in the directory. A compositor whose seat session went inactive
      # keeps its socket and accepts clients, it just has no outputs and paints
      # nowhere -- so "first wayland-* wins" silently sends the board to a
      # screen that does not exist. Ask each candidate for an output instead,
      # newest socket first, and take the one with a screen behind it.
      candidates=()
      if [ -n "''${WAYLAND_DISPLAY:-}" ]; then
        candidates+=("$WAYLAND_DISPLAY")
      fi
      while IFS= read -r socket; do
        candidates+=("''${socket##*/}")
      done < <(find "$runtime_dir" -maxdepth 1 -name 'wayland-*' ! -name '*.lock' -printf '%T@ %p\n' \
        | sort -rn | cut -d' ' -f2-)

      wayland_display=""
      for candidate in ''${candidates[@]+"''${candidates[@]}"}; do
        [ -S "$runtime_dir/$candidate" ] || continue
        if WAYLAND_DISPLAY="$candidate" timeout 5 wayland-info 2>/dev/null | grep -q "wl_output"; then
          wayland_display="$candidate"
          break
        fi
      done

      if [ -z "$wayland_display" ]; then
        echo "tv-run: no Wayland session is driving the TV" >&2
        if ! systemctl is-active --quiet greetd; then
          echo "        greetd is not running. Start it with: sudo systemctl start greetd" >&2
        elif [ -n "''${candidates[*]:-}" ]; then
          echo "        a compositor is up but has no output: the TV is off or unplugged," >&2
          echo "        or its seat session went inactive. Check /sys/class/drm/*/status," >&2
          echo "        then: sudo systemctl restart greetd" >&2
        else
          echo "        greetd is up but labwc has no socket; check: journalctl -u greetd -e" >&2
        fi
        exit 1
      fi
      export WAYLAND_DISPLAY="$wayland_display"

      program="$(command -v "$1" || true)"
      if [ -z "$program" ]; then
        echo "tv-run: program not found: $1" >&2
        exit 127
      fi
      shift

      app_name="$(basename "$program" | tr -cd 'A-Za-z0-9_.-')"
      unit="tv-$app_name-$(date +%s)-$$"
      unit_environment=(
        "--setenv=XDG_RUNTIME_DIR=$runtime_dir"
        "--setenv=DBUS_SESSION_BUS_ADDRESS=$DBUS_SESSION_BUS_ADDRESS"
        "--setenv=WAYLAND_DISPLAY=$wayland_display"
      )
      for key in DISPLAY NIXOS_OZONE_WL MOZ_ENABLE_WAYLAND GRAPHIDE_MONOLITH \
                 XDG_SESSION_TYPE XDG_CURRENT_DESKTOP; do
        if [ -n "''${!key:-}" ]; then
          unit_environment+=("--setenv=$key=''${!key}")
        fi
      done

      # One client on the TV. Previous tv-run units keep running after SSH
      # disconnects, so a second launch would otherwise stack another window.
      mapfile -t old < <(systemctl --user list-units --type=service --state=active --no-legend --plain -- 'tv-*' | awk '{print $1}')
      if (( ''${#old[@]} )); then
        systemctl --user stop -- "''${old[@]}"
      fi

      exec systemd-run --user --collect \
        --unit="$unit" \
        --property=Type=exec \
        "''${unit_environment[@]}" \
        -- "$program" "$@"
    '';
  };
in
{
  # A deliberately small physical seat for the attached TV. This does not
  # import system/head or home/desktop: there is no GDM, GNOME, Hyprland,
  # Plymouth, portal stack or collection of desktop applications.
  programs.xwayland.enable = true;

  services.greetd = {
    enable = true;
    settings = {
      # initial_session starts the seat without an interactive login at boot.
      # When it exits, greetd falls through to default_session; making them
      # identical turns that fallback into the compositor restart path.
      initial_session = session;
      default_session = session;
    };
  };

  # greetd's module only attaches to graphical.target. This host boots and
  # stays on multi-user (SSH, containers) until someone isolates graphical,
  # so a switch that only enables greetd leaves it loaded and dead. Pull it
  # into the target that is actually running, and restart on switch: this
  # seat is an appliance, not a login the rebuild should preserve.
  systemd.services.greetd = {
    wantedBy = [ "multi-user.target" ];
    restartIfChanged = lib.mkForce true;

    # Stopping greetd does not stop the compositor it started. logind has
    # already moved that process into its own session scope, so it outlives
    # the unit's cgroup: every switch used to leave another labwc running in
    # a `closing` session, holding wayland-N and no output, while the live
    # seat moved on to wayland-N+1. Reap them either side of the unit.
    #
    # `pkill -x labwc` and not `loginctl terminate-user`: the seat user is
    # also the SSH user, and terminating them would kill the session doing
    # the rebuild. The `-` prefixes ignore pkill's exit 1 for "none matched".
    serviceConfig = {
      ExecStartPre = [ "-${pkgs.procps}/bin/pkill --euid ${user} --exact labwc" ];
      ExecStopPost = [ "-${pkgs.procps}/bin/pkill --euid ${user} --exact labwc" ];
    };
  };

  systemd.services.tv-output-watch = {
    description = "Log TV connector changes and restore the seat when the TV returns";
    wantedBy = [ "multi-user.target" ];
    after = [ "greetd.service" ];
    serviceConfig = {
      ExecStart = "${tvOutputWatch}/bin/tv-output-watch";
      Restart = "always";
      RestartSec = "5s";
    };
  };

  # labwc runs this after creating the Wayland and optional XWayland sockets.
  # Importing the values into the user manager is what lets `tv-run` create
  # independent services from SSH without inheriting the SSH connection.
  # Maximize every client. The compositor stays up so SSH can attach; the
  # launcher policy (stop the previous tv-* unit) is what keeps it one-at-a-time.
  # Maximize rather than ToggleFullscreen: chromium --kiosk is already
  # fullscreen, and toggling would take it back out.
  environment.etc."xdg/labwc/rc.xml".text = ''
    <?xml version="1.0"?>
    <labwc_config>
      <core>
        <decoration>client</decoration>
        <gap>0</gap>
      </core>
      <windowRules>
        <windowRule identifier="*" serverDecoration="no">
          <action name="Maximize"/>
        </windowRule>
      </windowRules>
    </labwc_config>
  '';

  environment.etc."xdg/labwc/autostart".text = ''
    ${pkgs.systemd}/bin/systemctl --user import-environment \
      DISPLAY WAYLAND_DISPLAY XDG_CURRENT_DESKTOP XDG_SESSION_TYPE \
      NIXOS_OZONE_WL MOZ_ENABLE_WAYLAND GRAPHIDE_MONOLITH
    ${pkgs.dbus}/bin/dbus-update-activation-environment --systemd \
      DISPLAY WAYLAND_DISPLAY XDG_CURRENT_DESKTOP XDG_SESSION_TYPE \
      NIXOS_OZONE_WL MOZ_ENABLE_WAYLAND GRAPHIDE_MONOLITH
  '' + lib.optionalString config.graphide.hackerboard.enable ''
    # The seat exists to show the board, and nothing started it: a boot -- or
    # the seat restarting after the TV came back -- left an empty screen until
    # somebody ssh'd in and ran `tv-run dashboard`. That is most of what made
    # this "unusable", and it is what makes tv-output-watch's restart an
    # actual recovery rather than a black screen with a compositor behind it.
    #
    # Through tv-run so the board is a systemd --user unit rather than a child
    # of the compositor: it can then be replaced, inspected and restarted the
    # same way as one launched over SSH.
    #
    # /run/current-system rather than a store path, so the board follows the
    # running system; this file is regenerated by the same switch that would
    # move that path anyway.
    ${tvRun}/bin/tv-run /run/current-system/sw/bin/dashboard
  '';

  environment.systemPackages = [
    pkgs.labwc
    pkgs.foot
    tvRun
  ];

  # The board on this TV is `tv-run dashboard`, started by the autostart above.
  # The launcher comes from graphide.hackerboard (system/graphide/hackerboard.nix),
  # which also generates its config; the seat's part is exporting
  # GRAPHIDE_MONOLITH above, which is how the wrapper finds the monorepo checkout.

  # Audio is socket-activated for applications that need the TV speakers.
  # No Bluetooth manager, mixer UI, JACK or 32-bit audio stack is installed.
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    pulse.enable = true;
  };

  # One compact font family is enough for terminals and GUI fallback text.
  fonts.packages = [ pkgs.dejavu_fonts ];
}
