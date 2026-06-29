{ config, lib, pkgs, inputs, ... }:
{
  imports = [ inputs.zen-browser.homeModules.default ];

  config = lib.mkIf config.desktop.enable {

    programs.zen-browser = {
      enable = true;

      policies = {
        DisableTelemetry = true;
        DisableFirefoxStudies = true;
        DontCheckDefaultBrowser = true;
        DisablePocket = true;
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
            # WebToEpub@Baka-tsuki.org, sabre@simplify.jobs, and
            # {91aa3897-2634-4a8a-9092-279db23a7689} (Zen Internet / @sameerasw)
            # persist from the existing profile — add here if you want them force-reinstalled
          ];
      };

      profiles.default = {
        isDefault = true;

        settings = {
          # ── Transparency (critical — both required on Linux) ────────────────────
          "browser.tabs.allow_transparent_browser" = true;
          "zen.widget.linux.transparency"          = true;
          "zen.theme.acrylic-elements"             = true;

          # ── Enable userChrome.css ───────────────────────────────────────────────
          "toolkit.legacyUserProfileCustomizations.stylesheets" = true;

          # ── Privacy ────────────────────────────────────────────────────────────
          "browser.contentblocking.category"                              = "strict";
          "network.dns.disablePrefetch"                                   = true;
          "network.http.referer.disallowCrossSiteRelaxingDefault.top_navigation" = true;
          "network.http.speculative-parallel-limit"                       = 0;
          "network.lna.blocking"                                          = true;

          # ── DNS over HTTPS (Cloudflare) ─────────────────────────────────────────
          "doh-rollout.mode"         = 2;
          "doh-rollout.self-enabled" = true;
          "doh-rollout.uri"          = "https://mozilla.cloudflare-dns.com/dns-query";

          # ── Downloads ──────────────────────────────────────────────────────────
          "browser.download.dir"        = "${config.home.homeDirectory}/Downloads/browserDownloads";
          "browser.download.folderList" = 2;

          # ── Session / tabs ─────────────────────────────────────────────────────
          # Load pinned tabs immediately (false = don't wait for demand)
          "browser.sessionstore.restore_pinned_tabs_on_demand" = false;
          # Open links in foreground instead of background
          "browser.tabs.loadInBackground" = false;

          # ── UI / devtools ──────────────────────────────────────────────────────
          "browser.aboutConfig.showWarning" = false;
          "browser.theme.toolbar-theme"     = 0;
          "devtools.chrome.enabled"         = true;

          # ── Sidebar ────────────────────────────────────────────────────────────
          "sidebar.visibility" = "hide-sidebar";

          # ── Zen view ───────────────────────────────────────────────────────────
          "zen.view.compact.enable-at-startup"  = false;
          "zen.view.grey-out-inactive-windows"  = false;
          "zen.view.window.scheme"              = 0;
          "zen.workspaces.continue-where-left-off" = true;

          # ── Transparent Zen mod settings (@sameerasw) ──────────────────────────
          "mod.sameerasw.zen_bg_blur"                  = "3px";
          "mod.sameerasw.zen_bg_color_enabled"         = true;
          "mod.sameerasw.zen_bg_img"                   = "url('https://github.com/sameerasw/my-internet/blob/main/wallpapers/zen-coral-01.jpeg?raw=true')";
          "mod.sameerasw.zen_bg_img_enabled"           = false;
          "mod.sameerasw.zen_bg_img_not_fullscreen"    = false;
          "mod.sameerasw.zen_bg_opacity"               = "0.8";
          "mod.sameerasw.zen_compact_sidebar_width"    = "165px";
          "mod.sameerasw.zen_no_shadow"                = false;
          "mod.sameerasw.zen_notab_img"                = "url('https://github.com/sameerasw/my-internet/blob/main/wave-light.png?raw=true')";
          "mod.sameerasw.zen_notab_img_opacity"        = "1";
          "mod.sameerasw.zen_notab_img_size"           = "150px";
          "mod.sameerasw.zen_tab_switch_anim"          = true;
          "mod.sameerasw.zen_trackpad_anim"            = false;
          "mod.sameerasw.zen_transparency_color"       = "#000000B8";
          "mod.sameerasw.zen_transparent_glance_enabled" = false;
          "mod.sameerasw.zen_transparent_sidebar_enabled" = true;
          "mod.sameerasw.zen_urlbar_zoom_anim"         = false;
          "mod.sameerasw_zen_animations"               = "1";
          "mod.sameerasw_zen_compact_sidebar_type"     = "0";
          "mod.sameerasw_zen_empty_tab_logo"           = "1";
          "mod.sameerasw_zen_light_tint"               = "";
        };

        search = {
          default = "brave";
          force = true;
          engines = {
            "brave" = {
              urls = [{
                template = "https://search.brave.com/search";
                params = [{ name = "q"; value = "{searchTerms}"; }];
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
              }];
              definedAliases = [ "!ny" ];
            };
            "PirateBay" = {
              urls = [{
                template = "https://thepiratebay.org/search.php";
                params = [{ name = "q"; value = "{searchTerms}"; }];
              }];
              iconUpdateURL = "https://thepiratebay.org/favicon.ico";
              definedAliases = [ "!tpb" ];
              updateInterval = 7 * 24 * 60 * 60 * 1000;
            };
          };
        };

        mods = [
          "642854b5-88b4-4c40-b256-e035532109df"  # Transparent Zen by @sameerasw
        ];

        userChrome = ''
          /* Center url bar text when not focused */
          #urlbar:not([focused]) .urlbar-input {
              text-align: center !important;
          }

          /* Floating url bar appear animation */
          @keyframes floating-urlbar-show {
              0%   { opacity: 0; scale: 0.8; }
              70%  { scale: 1.02; }
              100% { opacity: 1; scale: 1; }
          }

          #urlbar[breakout-extend] {
              animation: 200ms floating-urlbar-show ease-out;
          }

          /* Search one-off engine buttons */
          .search-one-offs {
              border-top: none !important;
              padding: 4px !important;
              margin: 0px 0px 7px 0px !important;
          }

          .searchbar-engine-one-off-item {
              border-radius: 8px !important;
              margin-right: 3px !important;
          }

          #urlbar-anon-search-settings {
              margin-right: 0px !important;
          }

          /* Prevent border/outline flashes during transitions */
          * {
              border: 0px solid transparent;
              outline: 0px solid transparent;
          }

          /* Dim unloaded (pending) tabs */
          .tabbrowser-tab[pending] {
              filter: grayscale(1);
              opacity: 0.5;
          }

          /* Smooth UI element animations */
          :is(
              .tab-background,
              .toolbarbutton-icon,
              .toolbarbutton-badge-stack,
              .toolbarbutton-1,
              .bookmark-item,
              .PanelUI-zen-profiles-item,
              .download-state,
              .urlbarView-row,
              .urlbarView-action,
              .searchbar-engine-one-off-item,
              #urlbar-search-mode-indicator,
              #tracking-protection-icon-container,
              #page-action-buttons > *,
              #identity-box > *,
              toolbarbutton,
              toolbaritem,
              button,
              menu,
              menuitem,
              tab
          ):not(#urlbar-container, #personal-bookmarks) {
              transition: all 0.15s ease !important;

              &:is(tab) {
                  transition: scale 0.15s ease !important;
              }

              &:is(:active, :not(tab)[open]) {
                  scale: 0.95 !important;
              }
          }
        '';
      };
    };

    # Helper: copy the AMO extension ID for a given addon URL → paste into ExtensionSettings
    home.packages = [
      (pkgs.writeShellScriptBin "nixffext" ''
        wl-copy "(extension \"$(printf "$1" | awk -F '/' '{printf $7 }')\" \"$(curl -s "$1" | tr ',' '\n' | grep byGUID | tail -n 1 | awk -F '"' '{printf $4}')\")" && notify-send "ext copied"
      '')
    ];

    xdg.configFile."tridactyl/tridactylrc".text = ''
      bind ;c hint -Jc [class*="expand"],[class*="togg"],[class="comment_folder"]

      bind d composite tabprev; tabclose #
      bind D tabclose
      bindurl reddit.com gu urlparent 4

      bindurl www.google.com f hint -Jc #search a
      bindurl www.google.com F hint -Jbc #search a

      bind gd tabdetach
      bind gD composite tabduplicate; tabdetach

      bind gr reader
      bind gR reader --tab

      js tri.browserBg.runtime.getPlatformInfo().then(os=>{const editorcmd = os.os=="linux" ? "foot nvim" : "auto"; tri.config.set("editorcmd", editorcmd)})

      set hintfiltermode vimperator-reflow
      set hintdelay 100
      xamo_quiet

      jsb browser.webRequest.onHeadersReceived.addListener(tri.request.clobberCSP,{urls:["<all_urls>"],types:["main_frame"]},["blocking","responseHeaders"])

      command translate js let googleTranslateCallback = document.createElement('script'); googleTranslateCallback.innerHTML = "function googleTranslateElementInit(){ new google.translate.TranslateElement(); }"; document.body.insertBefore(googleTranslateCallback, document.body.firstChild); let googleTranslateScript = document.createElement('script'); googleTranslateScript.charset="UTF-8"; googleTranslateScript.src = "https://translate.google.com/translate_a/element.js?cb=googleTranslateElementInit&tl=&sl=&hl="; document.body.insertBefore(googleTranslateScript, document.body.firstChild);

      command nixext composite get_current_url | ! nixffext

      set smoothscroll true
      bind J tabnext
      bind K tabprev

      autocmd DocStart ^http(s?)://youtube.com js tri.excmds.urlmodify("-t", "youtube.com", "inv.nadeko.net")
      autocmd DocStart ^http(s?):// js tri.excmds.urlmodify("-t", "youtube.com", "inv.nadeko.net")
    '';
  };
}
