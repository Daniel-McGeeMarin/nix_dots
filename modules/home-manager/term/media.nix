{ lib, config, pkgs, ... }:
{
  config = lib.mkIf config.media.enable {
    programs.mpv.enable = true;
    home.packages = with pkgs; [
      yt-dlp
      mpc
      unfree.ffmpeg-full
      imagemagick
    ];
  };
}
