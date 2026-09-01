{ pkgs, lib, config, ... }:
{
  imports = [
    ./apps
    ./modules
  ];

  options.media.enable = lib.mkEnableOption "media CLI tools (ffmpeg, imagemagick, yt-dlp, mpc)" // {
    default = true;
  };

  config = {
    home.packages = with pkgs; [
      # ── Shell utilities ───────────────────────────────────────────────────────
      fastfetch                            # system info display
      jq                                   # JSON processor
      libnotify                            # send desktop notifications from terminal

      # ── TUI monitors ──────────────────────────────────────────────────────────
      btop                                 # resource/process monitor
    ]
    # ffmpeg-full alone is several hundred MB, and none of this is any use on a
    # box with no display and no music daemon — hence the switch rather than an
    # unconditional list.
    ++ lib.optionals config.media.enable [
      # ── Media (CLI) ───────────────────────────────────────────────────────────
      yt-dlp                               # video downloader (YouTube etc.)
      mpc                                  # MPD client for terminal playback control
      unfree.ffmpeg-full                   # media encoding/conversion
      imagemagick                          # image manipulation
    ];

    programs.gpg.enable = true;
  };
}
