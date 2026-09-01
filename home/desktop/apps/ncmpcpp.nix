{ config, lib, ... }:
{
  config = {
    services.mpd.enable = true;
    programs.ncmpcpp = {
      enable = true;
      bindings = [
        { key = "h"; command = "previous_column"; }
        { key = "j"; command = "scroll_down"; }
        { key = "k"; command = "scroll_up"; }
        { key = "l"; command = "next_column"; }
        { key = "J"; command = [ "select_item" "scroll_down" ]; }
        { key = "K"; command = [ "select_item" "scroll_up" ]; }
        { key = "."; command = "show_lyrics"; }
        { key = "n"; command = "next_found_item"; }
        { key = "N"; command = "previous_found_item"; }
        { key = "ctrl-u"; command = "page_up"; }
        { key = "ctrl-d"; command = "page_down"; }
      ];
    };
  };
}
