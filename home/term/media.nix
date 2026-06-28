{ lib, config, pkgs, ... }:
{
  config = lib.mkIf config.desktop.enable {
    home.packages = with pkgs; [
      yt-dlp
      mpc
      unfree.ffmpeg-full
      imagemagick
    ];
  };
}
