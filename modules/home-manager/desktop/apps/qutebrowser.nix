{ config, lib, pkgs, ... }:

let
  # Define the raw URL of the Catppuccin theme setup script
  themeUrl = "https://raw.githubusercontent.com/catppuccin/qutebrowser/main/setup.py";
in

{
  config = lib.mkIf config.desktop.enable {

    home.packages = with pkgs; [
      keyutils
      qutebrowser
    ];
    
    



    xdg.mimeApps.defaultApplications = {
      "text/html" = "org.qutebrowser.qutebrowser.desktop";
      "x-scheme-handler/http" = "org.qutebrowser.qutebrowser.desktop";
      "x-scheme-handler/https" = "org.qutebrowser.qutebrowser.desktop";
    };

    # Fetch the theme directly from GitHub using curl
    programs.qutebrowser = {
      enable = true;

      searchEngines = {
        "DEFAULT" = "https://search.brave.com/search?q={}";
        "nix" = "https://search.nixos.org/packages?query={}";
        "wiki" = "https://en.wikipedia.org/w/index.php?search={}";
        "gpt" = "https://chat.openai.com/?q={}";
        "c" = "https://chat.openai.com/?q={}";


      };

      # extraConfig = ''
      #   import os
      #   from urllib.request import urlopen
      #
      #   # Load autoconfig (use this if the rest of your config is empty)
      #   config.load_autoconfig()
      #
      #   # If the theme.py file doesn't exist in the config directory, download it
      #   if not os.path.exists(config.configdir / "theme.py"):
      #       theme = "${themeUrl}"
      #       with urlopen(theme) as themehtml:
      #           with open(config.configdir / "theme.py", "a") as file:
      #               file.writelines(themehtml.read().decode("utf-8"))
      #
      #   # If theme.py exists, import and apply the theme
      #   if os.path.exists(config.configdir / "theme.py"):
      #       import theme
      #       theme.setup(c, 'frappe', True)  # 'mocha' is the theme flavor (can be 'mocha', 'macchiato', 'frappe', or 'latte')
      # '';# Other qutebrowser settings...
      #

      extraConfig = ''
        import os
        from urllib.request import urlopen

        config.load_autoconfig()

        # THEME ###########################################################
        if not os.path.exists(config.configdir / "theme.py"):
            theme = "${themeUrl}"
            with urlopen(theme) as themehtml:
                with open(config.configdir / "theme.py", "a") as file:
                    file.writelines(themehtml.read().decode("utf-8"))

        if os.path.exists(config.configdir / "theme.py"):
            import theme
            theme.setup(c, 'frappe', True)

        # CURSOR MODE SWITCHING ###########################################
        normal_css = os.path.expanduser("~/.config/qutebrowser/cursor-normal.css")
        insert_css = os.path.expanduser("~/.config/qutebrowser/cursor-insert.css")

        # Default cursor (normal mode)
        config.set("content.user_stylesheets", [normal_css])

        # Insert mode hook — automatic, no keybind needed
        config.on_mode_enter('insert',
            lambda: config.set("content.user_stylesheets", [insert_css]))

        # Leave insert mode → back to normal cursor
        config.on_mode_leave('insert',
            lambda: config.set("content.user_stylesheets", [normal_css]))
      '';








      keyBindings.normal = {
        ",b" = "spawn --userscript bitwarden";
      };

      settings = {
        "colors.webpage.preferred_color_scheme" = "dark";
        "colors.webpage.darkmode.enabled" = false;
        "colors.webpage.darkmode.algorithm" = "lightness-cielab";
        "colors.webpage.darkmode.policy.images" = "never"; # Don't invert images


        "auto_save.session" = true;
        "tabs.position" = "left";
        "tabs.width" = 100;
        "completion.shrink" = true;


      };



    };
  };
}

