{ pkgs, ... }:
# Resource ceilings for the desktop.
#
# Heavy AI-agent workloads on long uptimes filled the 126 GB root filesystem to
# 95%: /tmp alone reached 20 GB across 6530 entries, and a single wide build
# (scancode with 22 workers, ~700 MB each) once left 310 MB of RAM free and made
# the machine unusable. Nothing here changes behaviour under normal load — it
# only bounds things that previously had no bound.
#
# Deliberately host-scoped rather than living in system/default.nix, which
# XiaServer also imports: an OOM killer that reaches for the largest process
# would target podman containers there.
let
  # Same trip point as the old earlyoom setup (5% MemAvailable AND 10%
  # SwapFree), but it opens a rofi list instead of SIGTERM-ing on its own.
  # Killing Hyprland / the session / the notifier would make things worse,
  # so those stay off the list; everything else is fair game.
  memGuard = pkgs.writeShellApplication {
    name = "mem-guard";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.gawk
      pkgs.gnugrep
      pkgs.libnotify
      pkgs.procps
      pkgs.rofi
    ];
    text = ''
      # mem-guard            watch memory and pop the picker when both
      #                      MemAvailable < 5% and SwapFree < 10%
      # mem-guard --now      open the picker immediately (for testing)

      mem_field() {
        awk -v k="$1:" '$1 == k { print $2; exit }' /proc/meminfo
      }

      mem_critical() {
        local avail total swap_free swap_total
        avail=$(mem_field MemAvailable)
        total=$(mem_field MemTotal)
        swap_free=$(mem_field SwapFree)
        swap_total=$(mem_field SwapTotal)
        [[ -n "$avail" && -n "$total" && "$total" -gt 0 ]] || return 1
        # earlyoom fires only when BOTH are below threshold
        if (( avail * 100 < total * 5 )); then
          if [[ -z "$swap_total" || "$swap_total" -eq 0 ]]; then
            return 0
          fi
          if (( swap_free * 100 < swap_total * 10 )); then
            return 0
          fi
        fi
        return 1
      }

      mem_summary() {
        awk '
          $1 == "MemAvailable:" { a = $2 }
          $1 == "MemTotal:"     { t = $2 }
          $1 == "SwapFree:"     { sf = $2 }
          $1 == "SwapTotal:"    { st = $2 }
          END {
            printf "%d%% RAM free", (t > 0) ? (a * 100 / t) : 0
            if (st > 0) printf ", %d%% swap free", sf * 100 / st
          }
        ' /proc/meminfo
      }

      ensure_wayland() {
        if [[ -n "''${WAYLAND_DISPLAY:-}" ]]; then
          return 0
        fi
        local sock
        for sock in "''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"/wayland-*; do
          if [[ -S "$sock" ]]; then
            WAYLAND_DISPLAY="''${sock##*/}"
            export WAYLAND_DISPLAY
            return 0
          fi
        done
        return 1
      }

      # comm is the 15-char kernel name. Keep anything whose death would
      # take down the session or this picker off the list.
      is_protected() {
        local comm="$1"
        case "$comm" in
          Hyprland|hyprland|systemd|systemd-*|init|sddm|gdm|greetd)
            return 0 ;;
          pipewire|pipewire-*|wireplumber|sshd|dbus-daemon|dbus-run-laun)
            return 0 ;;
          quickshell|.quickshell-wra|caelestia-shell|caelestia|mem-guard|rofi)
            return 0 ;;
        esac
        return 1
      }

      process_lines() {
        # rss is kB. Skip the tiny stuff so the list is the actual hogs.
        ps -eo rss=,pid=,comm= --no-headers --sort=-rss | while read -r rss pid comm; do
          [[ "$rss" =~ ^[0-9]+$ && "$pid" =~ ^[0-9]+$ ]] || continue
          (( rss >= 81920 )) || continue
          is_protected "$comm" && continue
          [[ "$pid" == "$$" ]] && continue
          printf '%5dM  %-16s  pid %s\n' "$((rss / 1024))" "$comm" "$pid"
        done | head -n 20
      }

      pick() {
        ensure_wayland || {
          echo "mem-guard: no Wayland display, cannot open rofi" >&2
          return 1
        }

        local lines choice pid
        lines=$(process_lines)
        if [[ -z "$lines" ]]; then
          notify-send -u critical "Memory low" "$(mem_summary). No killable process above 80M."
          return 1
        fi

        notify-send -u critical "Memory low" "$(mem_summary). Pick a process to kill, or Esc to dismiss."

        # Compact the app-launcher theme: one column, no wallpaper header.
        choice=$(printf '%s\n' "$lines" | rofi -dmenu -i \
          -p "Memory low — kill which?  ($(mem_summary))" \
          -theme-str 'window { width: 42%; }' \
          -theme-str 'inputbar { padding: 12px; background-image: none; }' \
          -theme-str 'listview { columns: 1; lines: 14; }' \
          -no-custom) || true

        [[ -n "$choice" ]] || return 2
        pid=$(printf '%s\n' "$choice" | awk '{ print $NF }')
        [[ "$pid" =~ ^[0-9]+$ ]] || return 1

        kill -TERM "$pid" 2>/dev/null || return 1
        notify-send "Memory" "Sent SIGTERM to pid $pid ($choice)"
        sleep 2
        if kill -0 "$pid" 2>/dev/null; then
          kill -KILL "$pid" 2>/dev/null || true
        fi
        return 0
      }

      if [[ "''${1:-}" == "--now" ]]; then
        pick
        exit 0
      fi

      cooldown=0
      while true; do
        if mem_critical; then
          now=$(date +%s)
          if (( now >= cooldown )); then
            if pick; then
              cooldown=$((now + 15))
            else
              # dismissed or failed: do not immediately re-pop
              cooldown=$((now + 90))
            fi
          fi
        fi
        sleep 5
      done
    '';
  };
in
{
  # /tmp is a real directory on the root ext4 volume, not a tmpfs, so on a
  # multi-day uptime nothing ever reclaimed it.
  boot.tmp.cleanOnBoot = true;

  systemd.tmpfiles.rules = [
    # Browser-automation profiles leaked by agent runs; 14 had accumulated at
    # ~120 MB each. Nothing cleans these up on its own.
    "R! /tmp/puppeteer_dev_firefox_profile-* - - - 1d"

    # The gred fork checkout: 3 GB, 20-35 minutes to build, and it holds
    # uncommitted work, so it must not sit anywhere cleanOnBoot can reach.
    #
    # Nothing defaults to /tmp/vscode-src any more. Every script in
    # gred/build/ has always defaulted to $XDG_CACHE_HOME/graphide/vscode-src,
    # and as of monolith 99943ab so does gred-patch-dev, which keys a
    # per-checkout sibling: .../graphide/vscode-src-<8 hex of the checkout>.
    #
    # This line is now only a compatibility shim for a BUILD_DIR=/tmp/vscode-src
    # typed by hand. Keep it, but do not treat it as the mechanism that makes
    # the fork tree survive a reboot — it maps one exact path, so between
    # gred 533f6f4 and monolith 99943ab the keyed trees it did NOT match were
    # silently deleted on every boot. The parent directory is the mechanism.
    # tmpfiles processes parents before children, so this is recreated after
    # cleanOnBoot empties /tmp.
    "L /tmp/vscode-src - - - - /home/xia/.cache/graphide/vscode-src"
  ];

  # Compressed swap in RAM, at higher priority than the disk partition, so
  # paging stops landing on the SSD (1.1 TB written in 5.6 days). memoryPercent
  # bounds the device's uncompressed capacity, not the RAM it consumes — zstd
  # runs about 3:1, so a 7.5 GB device costs roughly 2.5 GB of real memory.
  zramSwap = {
    enable = true;
    algorithm = "zstd";
    memoryPercent = 25;
  };

  systemd.user.services.mem-guard = {
    description = "Low-memory process picker";
    wantedBy = [ "graphical-session.target" ];
    after = [ "graphical-session.target" ];
    partOf = [ "graphical-session.target" ];
    serviceConfig = {
      ExecStart = "${memGuard}/bin/mem-guard";
      Restart = "on-failure";
      RestartSec = "5s";
    };
  };

  environment.systemPackages = [ memGuard ];
}
