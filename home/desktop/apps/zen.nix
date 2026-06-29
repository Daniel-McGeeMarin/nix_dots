{ config, lib, pkgs, inputs, ... }:
let
  # zen-beta (current) reads profiles from ~/.zen/, not ~/.config/zen/ which the
  # HM module targets. Manage profile-specific files directly via home.file.
  profile = ".zen/543mgzlr.Default (release)";
in
{
  imports = [ inputs.zen-browser.homeModules.default ];

  config = lib.mkIf config.desktop.enable {

    # Package + policies only — these work because policies go into the binary
    # wrapper (distribution/policies.json), not the profile directory.
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
          ];
      };
    };

    home.file = {
      "${profile}/user.js".text = ''
        user_pref("browser.tabs.allow_transparent_browser", true);
        user_pref("zen.widget.linux.transparency", true);
        user_pref("zen.theme.acrylic-elements", true);
        user_pref("toolkit.legacyUserProfileCustomizations.stylesheets", true);
        user_pref("browser.contentblocking.category", "strict");
        user_pref("network.dns.disablePrefetch", true);
        user_pref("network.http.referer.disallowCrossSiteRelaxingDefault.top_navigation", true);
        user_pref("network.http.speculative-parallel-limit", 0);
        user_pref("network.lna.blocking", true);
        user_pref("doh-rollout.mode", 2);
        user_pref("doh-rollout.self-enabled", true);
        user_pref("doh-rollout.uri", "https://mozilla.cloudflare-dns.com/dns-query");
        user_pref("browser.download.dir", "${config.home.homeDirectory}/Downloads/browserDownloads");
        user_pref("browser.download.folderList", 2);
        user_pref("browser.sessionstore.restore_pinned_tabs_on_demand", false);
        user_pref("browser.tabs.loadInBackground", false);
        user_pref("browser.aboutConfig.showWarning", false);
        user_pref("browser.theme.toolbar-theme", 0);
        user_pref("devtools.chrome.enabled", true);
        user_pref("sidebar.visibility", "hide-sidebar");
        user_pref("zen.view.compact.enable-at-startup", false);
        user_pref("zen.view.grey-out-inactive-windows", false);
        user_pref("zen.view.window.scheme", 0);
        user_pref("zen.workspaces.continue-where-left-off", true);
        user_pref("mod.sameerasw.zen_bg_blur", "3px");
        user_pref("mod.sameerasw.zen_bg_color_enabled", true);
        user_pref("mod.sameerasw.zen_bg_img", "url('https://github.com/sameerasw/my-internet/blob/main/wallpapers/zen-coral-01.jpeg?raw=true')");
        user_pref("mod.sameerasw.zen_bg_img_enabled", false);
        user_pref("mod.sameerasw.zen_bg_img_not_fullscreen", false);
        user_pref("mod.sameerasw.zen_bg_opacity", "0.8");
        user_pref("mod.sameerasw.zen_compact_sidebar_width", "165px");
        user_pref("mod.sameerasw.zen_no_shadow", false);
        user_pref("mod.sameerasw.zen_notab_img", "url('https://github.com/sameerasw/my-internet/blob/main/wave-light.png?raw=true')");
        user_pref("mod.sameerasw.zen_notab_img_opacity", "1");
        user_pref("mod.sameerasw.zen_notab_img_size", "150px");
        user_pref("mod.sameerasw.zen_tab_switch_anim", true);
        user_pref("mod.sameerasw.zen_trackpad_anim", false);
        user_pref("mod.sameerasw.zen_transparency_color", "#000000B8");
        user_pref("mod.sameerasw.zen_transparent_glance_enabled", false);
        user_pref("mod.sameerasw.zen_transparent_sidebar_enabled", true);
        user_pref("mod.sameerasw.zen_urlbar_zoom_anim", false);
        user_pref("mod.sameerasw_zen_animations", "1");
        user_pref("mod.sameerasw_zen_compact_sidebar_type", "0");
        user_pref("mod.sameerasw_zen_empty_tab_logo", "1");
        user_pref("mod.sameerasw_zen_light_tint", "");
      '';

      "${profile}/chrome/userChrome.css" = {
        force = true;
        text = ''
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

          /* Prevent border/outline flashes */
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
