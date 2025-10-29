{ config, lib, pkgs, ... }:

let
  # Define the raw URL of the Catppuccin theme setup script
  themeUrl = "https://raw.githubusercontent.com/catppuccin/qutebrowser/main/setup.py";
in

{
  config = lib.mkIf config.desktop.enable {

    home.packages = with pkgs; [
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
        "DEFAULT" = "https://duckduckgo.com/?q={}";
        "ddg" = "https://duckduckgo.com/?q={}";
        "g" = "https://google.com/search?q={}";
        "nix" = "https://search.nixos.org/options?query={}";
        "pkg" = "https://search.nixos.org/packages?query={}";
        "wiki" = "https://wiki.nixos.org/w/index.php?search={}";
      };

      extraConfig = ''
        import os
        from urllib.request import urlopen

        # Load autoconfig (use this if the rest of your config is empty)
        config.load_autoconfig()

        # If the theme.py file doesn't exist in the config directory, download it
        if not os.path.exists(config.configdir / "theme.py"):
            theme = "${themeUrl}"
            with urlopen(theme) as themehtml:
                with open(config.configdir / "theme.py", "a") as file:
                    file.writelines(themehtml.read().decode("utf-8"))

        # If theme.py exists, import and apply the theme
        if os.path.exists(config.configdir / "theme.py"):
            import theme
            theme.setup(c, 'frappe', True)  # 'mocha' is the theme flavor (can be 'mocha', 'macchiato', 'frappe', or 'latte')
      '';# Other qutebrowser settings...


      settings = {
        # "content.blocking.enabled" = true;
        # "content.blocking.method" = "both";
        # "content.blocking.adblock.lists" = [
        #   "easylist"
        #   "easyprivacy"
        #   "easylist-annoyances"
        #   "ublock-annoyances"
        #   "ublock-privacy"
        # ];

        "colors.webpage.darkmode.enabled" = true;
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

