{ pkgs, config, ... }:
{
  programs.foot = {
    server.enable = true;
    settings = {
      main = {
        font = "FiraCodeNerdFont-Regular:size=10";
        dpi-aware = true;
      };
      colors = {
        alpha = 0.8;
      };
    };
  };
}
