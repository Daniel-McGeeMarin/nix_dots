{ pkgs, lib, config, ... }:
{
  xdg.mimeApps.defaultApplications = lib.mkIf config.programs.zathura.enable {
    "application/pdf" = "org.pwmt.zathura.desktop";
  };
  programs.zathura = {
    mappings = {
      "=" = "zoom in";
    };
    options = with config.colorScheme.palette; {
      default-bg = "#${base00}";
      default-fg = "#${base0A}";
      adjust-open = "best fit";
      font = "FiraCodeNerdFont-Regular 10";
      notification-error-bg = "#${base0A}";
      notification-error-fg = "#${base08}";
      notification-warning-bg = "#${base0A}";
      notification-warning-fg = "#${base08}";
      notification-bg = "#${base0A}";
      notification-fg = "#${base09}";
      completion-group-bg = "#${base03}";
      completion-group-fg = "#${base00}";
      completion-bg = "#${base02}";
      completion-fg = "#${base0F}";
      completion-highlight-bg = "#${base0A}";
      completion-highlight-fg = "#${base02}";
      index-bg = "#${base02}";
      index-fg = "#${base0F}";
      index-active-bg = "#${base0A}";
      index-active-fg = "#${base02}";
      inputbar-bg = "#${base0A}";
      inputbar-fg = "#${base02}";
      statusbar-bg = "#${base02}";
      statusbar-fg = "#${base0F}";
      highlight-color = "#${base02}7F";
      highlight-active-color = "#${base0D}7F";
      render-loading = "true";
      render-loading-fg = "#${base02}";
      render-loading-bg = "#${base02}";
      recolor = "true";
      recolor-lightcolor = "#${base00}";
      recolor-darkcolor = "#${base05}";
      recolor-keephue = "true";
      selection-clipboard = "clipboard";
    };
  };
}
