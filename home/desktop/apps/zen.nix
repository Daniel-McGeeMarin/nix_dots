{ config, lib, pkgs, inputs, ... }:
let
  potatofox = pkgs.fetchFromGitea {
    domain = "codeberg.org";
    owner  = "da157";
    repo   = "PotatoFox";
    rev    = "80e926aeb20f61a927ec0be7a73835d5533227eb";
    hash   = "sha256-WkUJytR6zPmq0vMCMlaEf3J8UM9XkY0IJa2Jn5OrO48=";
  };
in
{
  config = lib.mkIf config.desktop.enable {

    programs.zen-browser = {
      enable = true;

      nativeMessagingHosts = [ pkgs.tridactyl-native ];

      policies = {
        DisableTelemetry = true;
        DisableFirefoxStudies = true;
        DontCheckDefaultBrowser = true;
        DisablePocket = true;
        DisableFirefoxAccounts = false;
        PasswordManagerEnabled = false;
        ExtensionSettings = with builtins;
          let extension = shortId: uuid: {
            name = uuid;
            value = {
              install_url = "https://addons.mozilla.org/en-US/firefox/downloads/latest/${shortId}/latest.xpi";
              installation_mode = "force_installed";
            };
          };
          in listToAttrs [
            (extension "ublock-origin"              "uBlock0@raymondhill.net")
            (extension "bitwarden-password-manager" "{446900e4-71c2-419f-a6a7-df9c091e268b}")
            (extension "video-downloadhelper"       "{b9db16a4-6edc-47ec-a1f4-b86292ed211d}")
            (extension "libredirect"                "7esoorv3@alefvanoon.anonaddy.me")
            (extension "darkreader"                 "addon@darkreader.org")
            (extension "tridactyl-vim"              "tridactyl.vim@cmcaine.co.uk")
            (extension "caelestiafox"               "caelestiafox@caelestia.org")
          ];
      };

      profiles.default = {
        isDefault = true;

        settings = {
          # ── Zen transparency ──────────────────────────────────────────────────
          "zen.widget.linux.transparency"                       = true;
          "browser.tabs.allow_transparent_browser"              = true;
          "browser.display.background_color"                    = "#00000000";
          "browser.display.background_color.dark"               = "#00000000";
          "toolkit.legacyUserProfileCustomizations.stylesheets" = true;
          "gfx.webrender.all"                                   = true;
          "layers.acceleration.force-enabled"                   = true;

          # ── Privacy ────────────────────────────────────────────────────────────
          "browser.contentblocking.category"                                      = "strict";
          "network.dns.disablePrefetch"                                           = true;
          "network.http.referer.disallowCrossSiteRelaxingDefault.top_navigation" = true;
          "network.http.speculative-parallel-limit"                               = 0;
          "network.lna.blocking"                                                  = true;

          # ── DNS over HTTPS (Cloudflare) ────────────────────────────────────────
          "doh-rollout.mode"         = 2;
          "doh-rollout.self-enabled" = true;
          "doh-rollout.uri"          = "https://mozilla.cloudflare-dns.com/dns-query";

          # ── Downloads ──────────────────────────────────────────────────────────
          "browser.download.dir"        = "${config.home.homeDirectory}/Downloads/browserDownloads";
          "browser.download.folderList" = 2;

          # ── Tab / session behaviour ────────────────────────────────────────────
          "browser.tabs.loadInBackground" = false;

          # ── UI ────────────────────────────────────────────────────────────────
          "browser.aboutConfig.showWarning" = false;
          "devtools.chrome.enabled"         = true;

          # ── Tridactyl: allow it on more pages ─────────────────────────────────
          "extensions.webextensions.restrictedDomains" = "";

          # ── PotatoFox required ─────────────────────────────────────────────────
          "svg.context-properties.content.enabled"    = true;
          "layout.css.has-selector.enabled"           = true;
          "browser.urlbar.suggest.calculator"         = true;
          "browser.urlbar.unitConversion.enabled"     = true;
          "browser.urlbar.trimHttps"                  = true;
          "browser.urlbar.trimURLs"                   = true;
          "widget.gtk.rounded-bottom-corners.enabled" = true;
          "browser.compactmode.show"                  = true;
          "widget.gtk.ignore-bogus-leave-notify"      = 1;
          "browser.uidensity"                         = 1;
          "uc.tweak.translucency"                     = true;
        };

        search = {
          default = "brave";
          force   = true;
          engines = {
            "brave" = {
              urls = [{ template = "https://search.brave.com/search"; params = [{ name = "q"; value = "{searchTerms}"; }]; }];
              definedAliases = [ "!br" ];
              iconUpdateURL   = "https://brave.com/favicon.ico";
              updateInterval  = 7 * 24 * 60 * 60 * 1000;
            };
          };
        };

        userChrome = ''
          @import url("pf/userChrome.css");

          :root {
              --uc-bg-opaque: var(
                  --lwt-accent-color,
                  light-dark(rgb(239, 239, 242), rgb(27, 26, 32))
              ) !important;

              --uc-bg-translucency: color-mix(
                  in oklab,
                  var(--uc-bg-opaque) 80%,
                  transparent
              ) !important;
          }

          .titlebar-buttonbox-container {
              display: none !important;
          }

          .tabbrowser-tab[pending] {
              filter: grayscale(1);
              opacity: 0.5;
          }
        '';

        userContent = ''
          @import url("pf/userContent.css");

          @-moz-document url-prefix("about:newtab"), url-prefix("about:home") {
            #root, .outer-wrapper, .activity-stream {
              background: transparent !important;
              background-color: transparent !important;
              background-image: none !important;
            }
          }
        '';
      };
    };

    # PotatoFox chrome assets for the Zen profile (profile path: ~/.config/zen/default/)
    home.file.".config/zen/default/chrome/pf" = {
      source = "${potatofox}/chrome";
      recursive = true;
    };
  };
}
