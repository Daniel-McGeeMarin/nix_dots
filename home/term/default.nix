{ pkgs, lib, ... }:
{
  imports = [
    ./apps
    ./modules
  ];

  home.packages = with pkgs; [
    # ── Shell utilities ───────────────────────────────────────────────────────
    fastfetch                              # system info display
    jq                                    # JSON processor
    libnotify                             # send desktop notifications from terminal

    # ── TUI monitors ──────────────────────────────────────────────────────────
    btop                                  # resource/process monitor

    # ── Media (CLI) ───────────────────────────────────────────────────────────
    yt-dlp                                # video downloader (YouTube etc.)
    mpc                                   # MPD client for terminal playback control
    unfree.ffmpeg-full                    # media encoding/conversion
    imagemagick                           # image manipulation
  ];

  programs.gpg.enable = true;
}
