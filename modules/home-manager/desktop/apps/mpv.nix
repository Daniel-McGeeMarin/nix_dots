{ config, lib, pkgs, inputs, ... }:
{
  config = lib.mkIf config.programs.mpv.enable {
    programs.mpv = {
      scripts = with pkgs.mpvScripts; [
        sponsorblock
        mpris
        thumbfast
        # quality-menu
        reload
        mpvacious
        mpv-cheatsheet
        webtorrent-mpv-hook
        autocrop
        uosc
        pkgs.unfree.mpvScripts.youtube-upnext
      ];
      bindings = {
        "Alt+," = "cycle-values play-dir - +";
        "F" = "script-binding quality_menu/video_formats_toggle";
        "Alt+f" = "script-binding quality_menu/audio_formats_toggle";
      };
      config = {
        osc = false;
        slang = "en";
        osd-bar = false;
        border = false;
        alang = "jp,en";
        profile = lib.mkDefault "high-quality";
      };

      scriptOpts = {
        sponsorblock = {
          categories = "music_offtopic,intro,outro,interaction,selfpromo";
          skip_categories = "music_offtopic,sponsor,selfpromo,outro";
        };
      };
    };
    xdg.mimeApps.defaultApplications = {
      "video/x-matroska" = "mpv.desktop";
      "video/mp4" = "mpv.desktop";
      "video/h264" = "mpv.desktop";
    };
  };
}
