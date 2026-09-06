{ config, pkgs, ... }:
let
  user = "XiaServer";
  monolith = "${config.graphide.demo.autoBuild.srcDir}/monolith";

  startTvSeat = pkgs.writeShellScript "start-tv-seat" ''
    export NIXOS_OZONE_WL=1
    export MOZ_ENABLE_WAYLAND=1
    export WLR_NO_HARDWARE_CURSORS=1
    export GRAPHIDE_MONOLITH=${monolith}
    exec ${pkgs.dbus}/bin/dbus-run-session -- ${pkgs.labwc}/bin/labwc
  '';

  session = {
    user = user;
    command = toString startTvSeat;
  };

  tvRun = pkgs.writeShellApplication {
    name = "tv-run";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.systemd
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
          DISPLAY|NIXOS_OZONE_WL|MOZ_ENABLE_WAYLAND|GRAPHIDE_MONOLITH)
            export "$key=$value"
            ;;
        esac
      done < <(systemctl --user show-environment)

      wayland_display="''${WAYLAND_DISPLAY:-}"
      if [ -z "$wayland_display" ]; then
        for socket in "$runtime_dir"/wayland-*; do
          if [ -S "$socket" ]; then
            wayland_display="''${socket##*/}"
            break
          fi
        done
      fi

      if [ -z "$wayland_display" ] || [ ! -S "$runtime_dir/$wayland_display" ]; then
        echo "tv-run: the TV Wayland session is not running" >&2
        echo "        check: systemctl status greetd" >&2
        exit 1
      fi

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
      for key in DISPLAY NIXOS_OZONE_WL MOZ_ENABLE_WAYLAND GRAPHIDE_MONOLITH; do
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
      DISPLAY WAYLAND_DISPLAY XDG_CURRENT_DESKTOP \
      NIXOS_OZONE_WL MOZ_ENABLE_WAYLAND GRAPHIDE_MONOLITH
    ${pkgs.dbus}/bin/dbus-update-activation-environment --systemd \
      DISPLAY WAYLAND_DISPLAY XDG_CURRENT_DESKTOP \
      NIXOS_OZONE_WL MOZ_ENABLE_WAYLAND GRAPHIDE_MONOLITH
  '';

  environment.systemPackages = [
    pkgs.labwc
    pkgs.foot
    tvRun
  ];

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
