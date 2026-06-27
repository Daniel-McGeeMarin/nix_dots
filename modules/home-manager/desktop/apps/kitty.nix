{ pkgs, config, ... }:
{
  home.sessionVariables."TERMINAL" = "kitty";
  programs.kitty = {
    settings = with config.colorScheme.palette; {
      font_family = "FiraCodeNerdFont-Regular";
      enable_audio_bell = true;
      font_size = 10;
      color0 = "#${base00}";
      color1 = "#${base08}";
      color2 = "#${base09}";
      color3 = "#${base0A}";
      color4 = "#${base0B}";
      color5 = "#${base0C}";
      color6 = "#${base0D}";
      color7 = "#${base0E}";
      color8 = "#${base03}";
      color9 = "#${base08}";
      color10 = "#${base09}";
      color11 = "#${base0A}";
      color12 = "#${base0B}";
      color13 = "#${base0C}";
      color14 = "#${base0D}";
      color15 = "#${base0E}";
      # alpha = 0.8;
      background = "#${base00}";
      foreground = "#${base05}";
      background_opacity = 0.8;
    };
  };
}

