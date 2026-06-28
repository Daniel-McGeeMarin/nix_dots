{ pkgs, lib, config, ... }:
{
  xdg.mimeApps.defaultApplications = lib.mkIf config.programs.zathura.enable {
    "application/pdf" = "org.pwmt.zathura.desktop";
  };
  programs.zathura = {
    mappings = {
      "=" = "zoom in";
    };
    options = {
      adjust-open = "best fit";
      font = "FiraCodeNerdFont-Regular 10";
      recolor = "true";
      recolor-keephue = "true";
      selection-clipboard = "clipboard";
    };
  };
}
