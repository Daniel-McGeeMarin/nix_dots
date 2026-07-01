{ config, lib, pkgs, inputs, ... }:
let
  potatofox = pkgs.fetchFromGitea {
    domain = "codeberg.org";
    owner  = "da157";
    repo   = "PotatoFox";
    rev    = "80e926aeb20f61a927ec0be7a73835d5533227eb";
    hash   = "sha256-WkUJytR6zPmq0vMCMlaEf3J8UM9XkY0IJa2Jn5OrO48=";
  };

  caelestiafoxNativeHost = pkgs.writeScript "caelestiafox-host" ''
    #!${pkgs.python3}/bin/python3
    import sys, json, struct, os, time

    state_dir = os.path.join(
        os.environ.get('XDG_STATE_HOME', os.path.expanduser('~/.local/state')),
        'caelestia'
    )
    scheme = os.path.join(state_dir, 'scheme.json')

    def send():
        with open(scheme) as f:
            msg = json.dumps(json.load(f), separators=(',', ':')).encode()
        sys.stdout.buffer.write(struct.pack('<I', len(msg)) + msg)
        sys.stdout.buffer.flush()

    try:
        send()
    except Exception:
        pass

    last = 0
    while True:
        time.sleep(1)
        try:
            mtime = os.path.getmtime(scheme)
            if mtime != last:
                last = mtime
                send()
        except Exception:
            pass
  '';
in
{
  config = lib.mkIf config.desktop.enable {

    programs.firefox = {
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
            (extension "zen-internet"               "{91aa3897-2634-4a8a-9092-279db23a7689}")
            (extension "caelestiafox"               "caelestiafox@caelestia.org")
            (extension "sidebery"                   "{3c078156-979c-498b-8990-85f7987dd929}")
          ];
      };

      profiles.default = {
        isDefault = true;

        settings = {
          # ── Transparency ───────────────────────────────────────────────────────
          "browser.tabs.allow_transparent_browser"              = true;
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
          @import url("pf/browser/main.css");
          @import url("pf/vars.css");

          /*
           * PotatoFox on Linux sets --uc-bg-opaque = ActiveCaption, which is
           * transparent when Hyprland owns the frame.  Override it to use
           * --lwt-accent-color (set by CaelestiaFox's browser.theme.update),
           * falling back to PotatoFox's built-in light/dark defaults so the
           * toolbar is never invisible even before CaelestiaFox first connects.
           */
          :root {
              --uc-bg-opaque: var(
                  --lwt-accent-color,
                  light-dark(rgb(239, 239, 242), rgb(27, 26, 32))
              ) !important;

              /* 80 % opacity — CaelestiaFox tint strongly visible, desktop shows through */
              --uc-bg-translucency: color-mix(
                  in oklab,
                  var(--uc-bg-opaque) 80%,
                  transparent
              ) !important;
          }

          /* ── Caelestia: remove window controls (handled by Hyprland) ────────── */
          .titlebar-buttonbox-container {
              display: none !important;
          }

          /* ── Pending tabs greyed out ───────────────────────────────────────── */
          .tabbrowser-tab[pending] {
              filter: grayscale(1);
              opacity: 0.5;
          }
        '';

        userContent = ''
          @import url("pf/userContent.css");
        '';
      };
    };

    # PotatoFox: place all chrome sub-files under a pf/ subdirectory so our
    # userChrome.css can @import them without clashing with HM-managed files.
    home.file.".mozilla/firefox/default/chrome/pf" = {
      source = "${potatofox}/chrome";
      recursive = true;
    };

    # Sidebery: managed storage seeds the settings key declaratively.
    # Panels/CSS are configured once manually in Sidebery's UI (they persist).
    home.file.".mozilla/managed-storage/{3c078156-979c-498b-8990-85f7987dd929}.json".text =
      builtins.toJSON {
        name        = "{3c078156-979c-498b-8990-85f7987dd929}";
        description = "Sidebery declarative settings";
        type        = "storage";
        data = {
          settings = {
            tabsTree                                = true;
            discardFolded                           = true;
            discardFoldedDelay                      = 30;
            discardFoldedDelayUnit                  = "sec";
            hideInact                               = true;
            activateLastTabOnPanelSwitching         = true;
            activateLastTabOnPanelSwitchingLoadedOnly = true;
            nativeScrollbars                        = false;
            skipEmptyPanels                         = true;
            hideEmptyPanels                         = true;
            colorScheme                             = "dark";
            animations                              = true;
          };
        };
      };

    home.file.".mozilla/native-messaging-hosts/caelestiafox.json" = {
      force = true;
      text = builtins.toJSON {
        name = "caelestiafox";
        description = "Native app for CaelestiaFox extension.";
        path = "${caelestiafoxNativeHost}";
        type = "stdio";
        allowed_extensions = [ "caelestiafox@caelestia.org" ];
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
