# Firefox Migration Plan

## Browser Choice: Plain Firefox vs Librewolf

**Recommendation: plain Firefox (`programs.firefox`)**

| | Firefox | Librewolf |
|---|---|---|
| HM module | `programs.firefox` — gold standard, full support | `programs.librewolf` — thin wrapper around the same module, works |
| profiles, userChrome, search, extensions | all fully declarative | same |
| Transparency | works via userChrome CSS on Wayland | same |
| Telemetry | disabled via `DisableTelemetry` policy + settings | disabled by default |
| Site compatibility | excellent | breaks some sites (aggressive defaults) |
| Speed | stock Firefox | similar |

Librewolf's aggressive privacy defaults (resistFingerprinting, etc.) regularly break
legitimate sites. With Firefox + policies + an arkenfox-style user.js subset we get the
same privacy wins with better compatibility. Librewolf is fine if you want to try it —
the HM module is nearly identical — but Firefox is the safer starting point.

## Vim Keybinds: already solved

The current Tridactyl config in zen.nix is a **standard Firefox extension** — it has
nothing Zen-specific. The `.tridactylrc` we have carries over unchanged. No fork needed.

There is no Firefox fork that adds native vim keybinds with good HM support. Tridactyl
is the standard solution and it is excellent.

## Settings: Keep vs Drop

### Keep (Firefox-compatible)
```
browser.tabs.allow_transparent_browser = true   ← core transparency pref, works in Firefox
toolkit.legacyUserProfileCustomizations.stylesheets = true
browser.contentblocking.category = "strict"
network.dns.disablePrefetch = true
network.http.referer.disallowCrossSiteRelaxingDefault.top_navigation = true
network.http.speculative-parallel-limit = 0
network.lna.blocking = true
doh-rollout.mode = 2
doh-rollout.self-enabled = true
doh-rollout.uri = "https://mozilla.cloudflare-dns.com/dns-query"
browser.download.dir = ~/Downloads/browserDownloads
browser.download.folderList = 2
browser.tabs.loadInBackground = false
browser.aboutConfig.showWarning = false
devtools.chrome.enabled = true
```

### Drop (Zen-specific, no Firefox equivalent)
```
zen.widget.linux.transparency        ← Zen only; Firefox uses CSS approach instead
zen.theme.acrylic-elements           ← Zen only
zen.view.*                           ← all Zen UI prefs
zen.workspaces.*                     ← Zen only
mod.sameerasw.*                      ← Zen mod prefs, replaced by Zen Internet extension
sidebar.visibility = "hide-sidebar"  ← Zen only
browser.theme.toolbar-theme          ← Zen only
browser.sessionstore.restore_pinned_tabs_on_demand ← drop, use Firefox defaults
```

### Add (Firefox-specific for transparency)
```
widget.gtk.rounded-bottom-corners.enabled = false  ← cleaner transparent edges
layers.acceleration.force-enabled = true           ← better compositing
gfx.webrender.all = true                           ← needed for smooth transparency
```

## Extensions

Force-install via `ExtensionSettings` policies (fully declarative, no NUR needed):

| Extension | UUID | Notes |
|---|---|---|
| uBlock Origin | `uBlock0@raymondhill.net` | keep |
| Bitwarden | `{446900e4-71c2-419f-a6a7-df9c091e268b}` | keep |
| Video DownloadHelper | `{b9db16a4-6edc-47ec-a1f4-b86292ed211d}` | keep |
| LibRedirect | `7esoorv3@alefvanoon.anonaddy.me` | keep |
| Dark Reader | `addon@darkreader.org` | keep |
| Tridactyl | `tridactyl.vim@cmcaine.co.uk` | vim keybinds — carry config over |
| **Zen Internet** | `{91aa3897-2634-4a8a-9092-279db23a7689}` | per-site transparency CSS — works on Firefox |
| **CaelestiaFox** | `caelestiafox@caelestia.org` | Caelestia integration |

Drop: WebToEpub, Simplify Jobs — not in current policies, were manual installs.

## Search Engines

Drop everything from the forked config (Nyaa, PirateBay).
Keep only Brave Search as default for now. User can add more later.

## Transparency: how it works in Firefox

Firefox on Wayland/Hyprland supports see-through window transparency via userChrome CSS:
- Set toolbar/sidebar backgrounds to `transparent` in userChrome.css
- Hyprland composites the wallpaper through those transparent areas
- `browser.tabs.allow_transparent_browser = true` removes the webpage backplate
- Zen Internet extension handles per-site CSS (same mod as in Zen)

Reference: https://github.com/rkcpn/simple-transparent-firefox (Hyprland-specific)

Blur in Hyprland config may need:
```
windowrule = opacity 0.9 0.9, ^(firefox)$
windowrule = blur, ^(firefox)$
```
(Exact rules depend on current hyprland.nix setup — check before applying.)

## Caelestia Integration

CaelestiaFox extension + native messaging host.
The `caelestia-firefox-integration/` and `native_app/` directories already exist in the
current Zen profile's chrome dir — these were set up by `caelestia install firefox`.
The native messaging host manifest needs to be placed at:
  `~/.mozilla/native-messaging-hosts/caelestiafox.json`
This can be managed via `home.file` in the new firefox.nix.

## Files to change

| File | Action |
|---|---|
| `home/desktop/apps/zen.nix` | delete |
| `home/desktop/apps/firefox.nix` | create (new `programs.firefox` config) |
| `home/desktop/apps/default.nix` | swap import, update mimeApps to `firefox.desktop` |
| `flake.nix` | remove `zen-browser` input |
| `system/default.nix` | nothing to change (zen already removed) |

## Migration steps (runtime, after nixswitch)

1. Copy profile data: `~/.zen/543mgzlr.Default (release)/` → `~/.mozilla/firefox/<profile>/`
   Files: `places.sqlite`, `key4.db`, `logins.json`, `cookies.sqlite`, `favicons.sqlite`,
   `cert9.db`, `storage/`, `browser-extension-data/`, `extension-settings.json`
2. Run Firefox once — it will pick up the migrated profile
3. Verify bookmarks, passwords, history
4. Delete `migrate-zen.sh` and `FIREFOX_PLAN.md` when done

## What the initial firefox.nix will have (phase 1)

- `programs.firefox.enable = true`
- Policies: DisableTelemetry, DisableFirefoxStudies, DisablePocket, DontCheckDefaultBrowser, ExtensionSettings
- One profile (`default`) with:
  - Transparency settings (user.js)
  - userChrome.css (transparent toolbar/sidebar + URL bar tweaks + tab animations)
  - Brave Search as default
- Tridactyl config carried over unchanged
- `nixffext` helper script

Phase 2 (later): add more search engines, refine settings, add CaelestiaFox native
messaging host, tune transparency to taste.
