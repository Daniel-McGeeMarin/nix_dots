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
  };
}

