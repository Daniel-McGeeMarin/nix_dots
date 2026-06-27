{ pkgs, config, ... }:
{
  programs.foot = {
    server.enable = true;
    settings = {
      main = {
        font = "FiraCodeNerdFont-Regular:size=10";
        dpi-aware = true;
      };
      colors = with config.colorScheme.palette; {
        regular0 = "${base00}";
        regular1 = "${base08}";
        regular2 = "${base09}";
        regular3 = "${base0A}";
        regular4 = "${base0B}";
        regular5 = "${base0C}";
        regular6 = "${base0D}";
        regular7 = "${base0E}";
        bright0 = "${base03}";
        bright1 = "${base08}";
        bright2 = "${base09}";
        bright3 = "${base0A}";
        bright4 = "${base0B}";
        bright5 = "${base0C}";
        bright6 = "${base0D}";
        bright7 = "${base0E}";
        alpha = 0.8;
        background = "${base00}";
        foreground = "${base05}";
        flash = "${base0A}";
        flash-alpha = 0.4;
      };
    };
  };
}
