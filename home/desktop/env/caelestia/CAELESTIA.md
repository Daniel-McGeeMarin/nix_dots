# Caelestia Shell — Agent Reference

This document is written for future AI agents working in this repo. It maps the entire
caelestia-shell codebase, explains every gotcha learned the hard way, and provides
copy-paste workflows for the most common tasks.

---

## Quick orientation

| What you want to change | Where to look |
|---|---|
| Workspace bar icons / label logic | `modules/bar/components/workspaces/Workspace.qml` |
| Bar layout, clock, tray, status | `modules/bar/Bar.qml`, `modules/bar/components/` |
| Bar config schema (what shell.json accepts) | `plugin/src/Caelestia/Config/barconfig.hpp` |
| Dashboard (left panel) | `modules/dashboard/` |
| App launcher | `modules/launcher/` (not listed above — explore if needed) |
| Lock screen | `modules/lock/` |
| Notifications | `modules/notifs/` |
| All config schema headers | `plugin/src/Caelestia/Config/*.hpp` |
| Live settings file | `confs/caelestia/shell.json` (this repo) |

The source lives in the nix store. Find it with:

```bash
# Get the store path for the current source
nix derivation show $(
  nix eval --raw /home/xia/nixos#homeConfigurations.XiaNix.config.programs.caelestia.package.drvPath
) 2>/dev/null | python3 -c "
import json,sys
d=json.load(sys.stdin); v=list(d.values())[0]
for s in v.get('inputSrcs',[]): print(s)
" | grep pgcy  # the source tarball has a content-addressed name
```

Or just grab it from the derivation used in the last build:

```bash
ls /nix/store/ | grep caelestia-shell | grep -v drv
# Pick the newest one, then:
# Source is the input with the long hash name ending in "-source"
nix derivation show /nix/store/<hash>-caelestia-shell-1.0.0.drv \
  | python3 -c "import json,sys; d=json.load(sys.stdin); v=list(d.values())[0]; [print(s) for s in v.get('inputSrcs',[])]"
```

Current pinned revision: `90a1b4662f6786e6091ee0b29c7b1431e2ff0bf6`
Current source store path: `/nix/store/xq83b9yawrmr3n9zs31sgdygz2nkg5m7-pgcy843fqn9ky50dp0gi22wlain8ilqj-source`

---

## Build architecture — READ THIS FIRST

The caelestia flake (`nix/default.nix`) compiles **three separate derivations** inside one
build. This is critical: `overrideAttrs` on the outer shell package does NOT automatically
patch the inner ones.

```
caelestia-shell (outer, QML files + wrapper)  ← our overrideAttrs patches reach here
  ├── plugin  (C++ QML plugin, libcaelestia-*.so)  ← SEPARATE derivation, patches do NOT reach here
  ├── extras  (C++ extras, separate derivation)
  └── m3shapes (Qt shapes module, separate derivation)
```

### What this means in practice

- **Patching QML files** (anything under `modules/`): works perfectly with `overrideAttrs`.
- **Patching the C++ plugin** (`plugin/src/...`): does NOT work with `overrideAttrs` on the
  shell. The plugin is built before the shell from a `lib.fileset.toSource` snapshot — it
  has its own independent derivation and our patches never touch it.
- **Conclusion**: if you need to change C++ config schema (add new keys to `barconfig.hpp`,
  etc.), you cannot do it by patching `caelestia-shell` alone. You would need to override
  the `plugin` derivation separately (see `nix/default.nix` line 90 — `plugin = stdenv.mkDerivation {...}`).

The active plugin is at runtime:
```bash
find /nix/store -maxdepth 5 -name "libcaelestia-config.so" 2>/dev/null | head -3
# verify a property exists:
strings <path>/libcaelestia-config.so | grep -i "yourProperty"
```

---

## Our patching system (`caelestiapatches/`)

```
caelestiapatches/
  default.nix           — applies patches via overrideAttrs, imported by hosts/XiaNix/home.nix
  workspace-icons.patch — current active patch (workspace label logic in Workspace.qml)
```

`default.nix` takes `caelestia-shell` (the `with-cli` package) and calls `overrideAttrs`
to append patches:

```nix
{ caelestia-shell }:
caelestia-shell.overrideAttrs (old: {
  patches = (old.patches or []) ++ [
    ./workspace-icons.patch
    # add future patches here
  ];
})
```

`hosts/XiaNix/home.nix` wires it in:

```nix
let
  patched-caelestia = import ../../caelestiapatches {
    caelestia-shell = inputs.caelestia-shell.packages.${pkgs.stdenv.hostPlatform.system}.with-cli;
  };
in {
  programs.caelestia = {
    enable = true;
    package = patched-caelestia;
    ...
  };
}
```

**Critical**: pass `with-cli` directly. Do NOT call `.override { withCli = true; }` after
`overrideAttrs` — `override` recreates the derivation from `callPackage` args and silently
drops all `overrideAttrs` patches.

---

## How to write a QML patch

### Step 1 — find the file in the source

```bash
SRC=/nix/store/xq83b9yawrmr3n9zs31sgdygz2nkg5m7-pgcy843fqn9ky50dp0gi22wlain8ilqj-source
# find the file you want
find $SRC/modules -name "*.qml" | grep -i workspace
# read it with line numbers
cat -n $SRC/modules/bar/components/workspaces/Workspace.qml
```

### Step 2 — write the patch

Unified diff format. The path in `---`/`+++` must be relative with `a/` and `b/` prefixes,
matching the source tree from its root.

**Hunk header math** — `@@ -L,S +L,S @@`:
- `-L,S`: starting line in original, S = (context before) + (removed lines) + (context after)
- `+L,S`: starting line in new file, S = (context before) + (added lines) + (context after)
- Use 3 context lines above and below the change (standard). Fewer is fine if needed to
  avoid unicode in context lines.

### Step 3 — UNICODE WARNING

The Write tool and Edit tool mangle supplementary Unicode codepoints (U+F0000 range — nerd
font icons). Any patch line containing these characters MUST be written via Python:

```python
python3 << 'EOF'
patch = """--- a/modules/bar/components/workspaces/Workspace.qml
+++ b/modules/bar/components/workspaces/Workspace.qml
@@ -48,5 +48,9 @@
             const label = Config.bar.workspaces.label || displayName;
             const occupiedLabel = Config.bar.workspaces.occupiedLabel || label;
             const activeLabel = Config.bar.workspaces.activeLabel || (root.isOccupied ? occupiedLabel : label);
-            return root.activeWsId === root.ws ? activeLabel : root.isOccupied ? occupiedLabel : label;
+            const icons = {""" + '{"1":"\U000F059F","2":"\U0000EA85"}' + """};
+            const wsIcon = icons[root.ws.toString()];
+            if (wsIcon && root.isOccupied)
+                return wsIcon;
+            return root.activeWsId === root.ws ? activeLabel : root.isOccupied ? occupiedLabel : label;
         }
"""
with open("/home/xia/nixos/caelestiapatches/my-patch.patch", "w", encoding="utf-8") as f:
    f.write(patch)
EOF
```

Or build the icons dict inline:

```python
icons = {"1": "\U000F059F", "2": "\U0000EA85", "3": "3"}
icons_js = "{" + ",".join(f'"{k}":"{v}"' for k,v in icons.items()) + "}"
# then embed icons_js into the patch string
```

### Step 4 — dry-run before adding to default.nix

```bash
SRC=/nix/store/xq83b9yawrmr3n9zs31sgdygz2nkg5m7-pgcy843fqn9ky50dp0gi22wlain8ilqj-source
patch --dry-run -p1 -d "$SRC" < /home/xia/nixos/caelestiapatches/my-patch.patch
# must exit 0. "fuzz N" warnings are OK as long as exit is 0.
```

### Step 5 — add to default.nix and rebuild

```nix
patches = (old.patches or []) ++ [
  ./workspace-icons.patch
  ./my-patch.patch
];
```

Then: `sudo nixos-rebuild switch --flake .#XiaNix`

---

## Source file map

All paths below are relative to the caelestia-shell source root.

### QML — bar

| File | Purpose |
|---|---|
| `modules/bar/Bar.qml` | Top-level bar, layout of all entries |
| `modules/bar/BarWrapper.qml` | Per-monitor wrapper |
| `modules/bar/components/workspaces/Workspace.qml` | Single workspace chip (label logic lives here) |
| `modules/bar/components/workspaces/Workspaces.qml` | Row of all workspace chips |
| `modules/bar/components/workspaces/ActiveIndicator.qml` | Animated active indicator |
| `modules/bar/components/workspaces/OccupiedBg.qml` | Background for occupied workspaces |
| `modules/bar/components/workspaces/SpecialWorkspaces.qml` | Special workspace handling |
| `modules/bar/components/Clock.qml` | Clock widget |
| `modules/bar/components/ActiveWindow.qml` | Active window title |
| `modules/bar/components/StatusIcons.qml` | Battery/network/etc icons |
| `modules/bar/components/Tray.qml` | System tray |
| `modules/bar/popouts/` | All bar hover popout panels |

### QML — other modules

| File | Purpose |
|---|---|
| `modules/background/Wallpaper.qml` | Wallpaper rendering |
| `modules/background/Visualiser.qml` | Audio visualiser |
| `modules/dashboard/` | Left-side dashboard panel (media, calendar, etc.) |
| `modules/lock/` | Lock screen |
| `modules/notifs/` | Notification popups |
| `shell.qml` | Root entry point, loads all modules |

### C++ plugin config headers

All in `plugin/src/Caelestia/Config/`. These define what keys `shell.json` accepts.
**Patching these requires overriding the `plugin` sub-derivation, not the shell.**

| File | Config path in shell.json |
|---|---|
| `barconfig.hpp` | `bar.*` — workspaces, clock, tray, status, entries |
| `appearanceconfig.hpp` | `appearance.*` |
| `backgroundconfig.hpp` | `background.*` |
| `dashboardconfig.hpp` | `dashboard.*` |
| `generalconfig.hpp` | `general.*` |
| `launcherconfig.hpp` | `launcher.*` |
| `lockconfig.hpp` | `lock.*` |
| `notifsconfig.hpp` | `notifs.*` |
| `osdconfig.hpp` | `osd.*` |
| `serviceconfig.hpp` | `services.*` |
| `sessionconfig.hpp` | `session.*` |
| `sidebarconfig.hpp` | `sidebar.*` |
| `utilitiesconfig.hpp` | `utilities.*` |
| `configobject.hpp` | Base class — `loadFromJson` / `toJsonObject` implementation |
| `tokens.hpp` | Design tokens (fonts, sizes, colours) — not in shell.json |

---

## shell.json

**Location in this repo**: `confs/caelestia/shell.json`
**Live location**: `~/.config/caelestia/shell.json` (symlinked from the repo path)

The C++ Config plugin reads this file on startup, deserializes it into typed C++ objects,
and **writes it back** — stripping any key it does not recognise from its schema.

### Rules

- You can change any value for an existing key freely — just edit the file and run
  `systemctl --user restart caelestia`.
- You cannot add new top-level or nested keys unless the corresponding C++ config class has
  a matching `CONFIG_PROPERTY(...)` declaration. Unknown keys are silently dropped on the
  next restart.
- The C++ plugin is a separate derivation. Adding a key to `barconfig.hpp` via
  `overrideAttrs` on the shell package does not work — see the build architecture section.

### Editing icons / workspace config without a rebuild

The current workspace icons are hardcoded in `caelestiapatches/workspace-icons.patch`.
To change them:

1. Edit the `icons` object inside the patch file (use Python if the icons contain nerd font
   codepoints — see the Unicode warning above).
2. Run `sudo nixos-rebuild switch --flake .#XiaNix`.

This is intentional. The icons live in the patch, not in `shell.json`, because adding
`workspaceIcons` to the C++ schema would require patching the plugin sub-derivation
which is a more complex change.

---

## Runtime diagnostics

```bash
# Which binary is running
cat /proc/$(systemctl --user show caelestia -p MainPID --value)/cmdline | tr '\0' '\n'

# Caelestia logs (last 50 lines)
journalctl --user -u caelestia -n 50

# Check if a config property exists in the running plugin
strings $(find /nix/store -maxdepth 5 -name "libcaelestia-config.so" 2>/dev/null | head -1) \
  | grep -i "yourProperty"

# Restart without rebuild (picks up shell.json changes)
systemctl --user restart caelestia

# Full rebuild + restart
sudo nixos-rebuild switch --flake .#XiaNix
```

---

## Current patches

### `workspace-icons.patch`

Modifies `modules/bar/components/workspaces/Workspace.qml`.

Adds a JS lookup table mapping workspace ID → nerd font icon. The icon is shown only when
the workspace is occupied (has windows). Workspaces without a special icon fall through to
the normal label logic (`occupiedLabel`, `activeLabel`, etc. from `shell.json`).

Workspaces with plain numbers (`"3": "3"`) show the number when occupied instead of the
default `occupiedLabel` glyph.

Current icon map:
```
ws1  󰖟  U+F059F  browser
ws2     U+EA85   terminal
ws3  3  (number)
ws4  4  (number)
ws5     U+F075   chat/discord
ws6  󰮂  U+F0B82  microphone
ws7  󰈮  U+F022E  files
ws8  󰅨  U+F0168  gaming
ws9  󰅱  U+F0171  book/reading
ws10 10 (number)
```

To change icons, edit the patch using the Python method above and run `nixswitch`.
