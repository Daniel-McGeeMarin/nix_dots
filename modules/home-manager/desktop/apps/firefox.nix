{ config, lib, pkgs, inputs, ... }:

let
  lock-false = {
    Value = false;
    Status = "locked";
  };
  lock-true = {
    Value = true;
    Status = "locked";
  };
  lock-empty-string = {
    Value = "";
    Status = "locked";
  };
in
{
  config = lib.mkIf config.programs.librewolf.enable {
    home.packages = [
      (pkgs.writeShellScriptBin "nixffext" ''
        wl-copy "(extension \"$(printf "$1" | awk -F '/' '{printf $7 }')\" \"$(curl -s "$1" | tr ',' '\n' | grep byGUID | tail -n 1 | awk -F '"' '{printf $4}')\")" && notify-send "ext copied"
      '')
    ];
    xdg.mimeApps.defaultApplications = {
      "text/html" = "librewolf.desktop";
      "x-scheme-handler/http" = "librewolf.desktop";
      "x-scheme-handler/https" = "librewolf.desktop";
      "x-scheme-handler/about" = "librewolf.desktop";
      "x-scheme-handler/unknown" = "librewolf.desktop";
    };
    home.file.csshacks = {
      source = inputs.firefox-css-hacks;
      target = ".librewolf/default/chrome/css-hacks";
    };
    programs.librewolf = {
      package = pkgs.librewolf.override {
        cfg = {
          enableGnomeExtensions = true;
        };
        nativeMessagingHosts = [
          pkgs.tridactyl-native
        ];
      };
      policies = {
        DisableTelemetry = true;
        DisableFirefoxStudies = true;
        DontCheckDefaultBrowser = true;
        DisablePocket = true;
        SearchBar = "unified";
        Preferences = {
          "extensions.pocket.enabled" = lock-false;
          "browser.topsites.contile.enabled" = lock-false;
          "browser.newtabpage.activity-stream.showSponsored" = lock-false;
          "browser.newtabpage.activity-stream.system.showSponsored" = lock-false;
          "browser.newtabpage.activity-stream.showSponsoredTopSites" = lock-false;

          browser.search.separatePrivateDefault = lock-false;
          "browser.search.defaultenginename" = "brave";
          "browser.search.order.1" = "brave";

          "browser.startup.page" = 3;
          "privacy.resistFingerprinting.block_mozAddonManager" = lock-true;
          "extensions.webextensions.restrictedDomains" = lock-empty-string;
        };
        ExtensionSettings = with builtins;
          let extension = shortId: uuid: {
            name = uuid;
            value = {
              install_url = "https://addons.mozilla.org/en-US/firefox/downloads/latest/${shortId}/latest.xpi";
              installation_mode = "force_installed";
            };
          };
          in
          listToAttrs [
            # EXTENSIONS
            (extension "multi-account-containers" "@testpilot-containers")
            (extension "ublock-origin" "uBlock0@raymondhill.net")
            (extension "bitwarden-password-manager" "{446900e4-71c2-419f-a6a7-df9c091e268b}")
            (extension "sponsorblock" "uMatrix@raymondhill.net")
            (extension "libredirect" "7esoorv3@alefvanoon.anonaddy.me")
            (extension "darkreader" "addon@darkreader.org")
            (extension "deep-fake-detector" "{ddd3c206-589e-431d-93d0-897378f9200a}")
            (extension "tridactyl-vim" "tridactyl.vim@cmcaine.co.uk")
            # lib.mkIf config.desktop.japanese.enable (extension "furiganaize" "{a2503cd4-4083-4c2f-bef2-37767a569867}")
            # lib.mkIf config.desktop.japanese.enable (extension "yomitan" "{6b733b82-9261-47ee-a595-2dda294a4d08}")
            (extension "furiganaize" "{a2503cd4-4083-4c2f-bef2-37767a569867}")
            (extension "yomitan" "{6b733b82-9261-47ee-a595-2dda294a4d08}")
            (extension "sponsorblock" "sponsorBlocker@ajay.app")
          ];
      };

      profiles = {
        default = {
          name = "default";
          isDefault = true;
          search = {
            default = "brave";
            force = true;
            engines = {
              "brave" = {
                urls = [{
                  template = "https://search.brave.com/search";
                  params = [
                    { name = "q"; value = "{searchTerms}"; }
                  ];
                }];
                definedAliases = [ "!br" ];
                iconUpdateURL = "https://brave.com/favicon.ico";
                updateInterval = 7 * 24 * 60 * 60 * 1000;
              };
              "nyaa" = {
                urls = [{
                  template = "https://nyaa.si/";
                  params = [
                    { name = "f"; value = "0"; }
                    { name = "c"; value = "0_0"; }
                    { name = "q"; value = "{searchTerms}"; }
                  ];
                  iconUpdateURL = "https://nyaa.si/static/favicon.png";
                  updateInterval = 7 * 24 * 60 * 60 * 1000;
                }];
                definedAliases = [ "!ny" ];
              };
              "PirateBay" = {
                urls = [{
                  template = "https://thepiratebay.org/search.php";
                  params = [
                    { name = "q"; value = "{searchTerms}"; }
                  ];
                }];
                iconUpdateURL = "https://thepiratebay.org/favicon.ico";
                definedAliases = [ "!tpb" ];
                updateInterval = 7 * 24 * 60 * 60 * 1000;
              };
            };
          };
          settings = {
            "browser.search.defaultenginename" = "brave";
            "browser.search.order.1" = "brave";
            "toolkit.legacyUserProfileCustomizations.stylesheets" = true;
            "sidebar.revamp" = true;
            "sidebar.verticalTabs" = true;
            "sidebar.main.tools" = "";
            "sidebar.expandOnHover" = true;
            "browser.tabs.groups.enabled" = true;
          };
          userChrome = /*css*/ ''
            @import url(css-hacks/chrome/blank_page_background.css);
            @import url(css-hacks/chrome/hide_toolbox_top_bottom_borders.css);
            @import url(css-hacks/chrome/minimal_popup_scrollbars.css);
            @import url(css-hacks/chrome/urlbar_centered_text.css);
            hbox.titlebar-spacer {
              display: none !important;
            }
            hbox#page-action-buttons {
              display: none !important;
            }
            hbox#nav-bar-customization-target {
              padding-left: var(--tab-inline-padding) !important;
            }
            toolbarbutton.titlebar-close {
              display: none !important;
            }
            toolbarbutton#back-button {
              display: none !important;
            }
            toolbarbutton#forward-button {
              display: none !important;
            }
            toolbarbutton#tabs-newtab-button {
              display: none !important;
            }
          '';
        };
      };
    };
    xdg.configFile."tridactyl/tridactylrc".text = /*vim*/ ''
      " Comment toggler for Reddit, Hacker News and Lobste.rs
      bind ;c hint -Jc [class*="expand"],[class*="togg"],[class="comment_folder"]

      bind d composite tabprev; tabclose #
      bind D tabclose
      " Make gu take you back to subreddit from comments
      bindurl reddit.com gu urlparent 4

      " Only hint search results on Google and DDG
      bindurl www.google.com f hint -Jc #search a
      bindurl www.google.com F hint -Jbc #search a

      " Handy multiwindow/multitasking binds
      bind gd tabdetach
      bind gD composite tabduplicate; tabdetach

      " Binds for new reader mode
      bind gr reader
      bind gR reader --tab

      " set editorcmd to foot, or use the defaults on other platforms
      js tri.browserBg.runtime.getPlatformInfo().then(os=>{const editorcmd = os.os=="linux" ? "foot lvim" : "auto"; tri.config.set("editorcmd", editorcmd)})

      " Sane hinting mode
      set hintfiltermode vimperator-reflow

      set hintdelay 100
      xamo_quiet

      jsb browser.webRequest.onHeadersReceived.addListener(tri.request.clobberCSP,{urls:["<all_urls>"],types:["main_frame"]},["blocking","responseHeaders"])

      command translate js let googleTranslateCallback = document.createElement('script'); googleTranslateCallback.innerHTML = "function googleTranslateElementInit(){ new google.translate.TranslateElement(); }"; document.body.insertBefore(googleTranslateCallback, document.body.firstChild); let googleTranslateScript = document.createElement('script'); googleTranslateScript.charset="UTF-8"; googleTranslateScript.src = "https://translate.google.com/translate_a/element.js?cb=googleTranslateElementInit&tl=&sl=&hl="; document.body.insertBefore(googleTranslateScript, document.body.firstChild);

      " quickly get ext
      command nixext composite get_current_url | ! nixffext

      " autocmd DocStart ^http(s?)://www.reddit.com js tri.excmds.urlmodify("-t", "www", "old")
      set smoothscroll true
      bind J tabnext
      bind K tabprev

      "Redirects
      autocmd DocStart ^http(s?)://youtube.com js tri.excmds.urlmodify("-t", "youtube.com", "inv.nadeko.net")
      autocmd DocStart ^http(s?):// js tri.excmds.urlmodify("-t", "youtube.com", "inv.nadeko.net")
    '';
  };
}
