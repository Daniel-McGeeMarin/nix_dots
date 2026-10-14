{ pkgs, config, ... }:
{
  home.sessionVariables."TERMINAL" = "kitty";
  programs.kitty = {
    settings = {
      font_family = "FiraCodeNerdFont-Regular";
      enable_audio_bell = true;
      font_size = 12;
      background_opacity = 0.65;
    };
    # Ctrl+V pastes text, so Wispr Flow's dictation lands in Codex and Claude
    # Code; an image on the clipboard or an editor in front still gets ^V.
    keybindings."ctrl+v" = "kitten smart_paste.py";
  };
  xdg.configFile."kitty/smart_paste.py".source = ./kitty-smart-paste.py;
}

