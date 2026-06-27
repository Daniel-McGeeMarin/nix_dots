{ lib, config, pkgs, ... }:
{
  config = lib.mkIf (config.media.enable && config.desktop.enable) {
    home.packages = with pkgs; [
      obs-studio
      audacity
      gimp
      inkscape
      sxiv
    ];
    services.flatpak.packages = [
      "org.qbittorrent.qBittorrent"
    ];
    services.mpd = {
      enable = true;
      # extraConfig = ''
      #   # must specify one or more outputs in order to play audio!
      #   # (e.g. ALSA, PulseAudio, PipeWire), see next sections
      # '';
    };
    programs.ncmpcpp = {
      enable = true;
      bindings = [
        { key = "h"; command = "previous_column"; }
        { key = "j"; command = "scroll_down"; }
        { key = "k"; command = "scroll_up"; }
        { key = "l"; command = "next_column"; }
        { key = "J"; command = [ "select_item" "scroll_down" ]; }
        { key = "K"; command = [ "select_item" "scroll_up" ]; }
        { key = "."; command = [ "show_lyrics" ]; }
        { key = "n"; command = [ "next_found_item" ]; }
        { key = "N"; command = [ "previous_found_item" ]; }
        { key = "ctrl-u"; command = [ "page_up" ]; }
        { key = "ctrl-d"; command = [ "page_down" ]; }
      ];
    };
  };
}
