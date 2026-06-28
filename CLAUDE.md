# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

```bash
# Apply system + home config (most common)
sudo nixos-rebuild switch --flake .#XiaNix

# Home Manager only (standalone)
home-manager switch --flake .#XiaNix

# Check flake without building
nix flake check

# Update a specific input
nix flake lock --update-input <input-name>

# Update all inputs
nix flake update
```

Use `nom` (`nix-output-monitor`) as a drop-in prefix for verbose, readable build output.

## Architecture

### Directory layout

```
hosts/        per-host configuration (XiaNix, XiaServer)
system/       NixOS modules (kernel, hardware, services)
home/         Home Manager modules (user environment, apps, desktop)
flake.nix     inputs + host outputs
```

### Flake structure

`flake.nix` defines two hosts:
- **XiaNix** — main desktop (LG Gram laptop)
- **XiaServer** — server (NVIDIA 1080 Ti, Jellyfin stack)

Each host has `nixosConfigurations.<name>` and `homeConfigurations.<name>`. The NixOS build at `hosts/XiaNix/configuration.nix` inlines Home Manager via `home-manager.users."xia" = import ./home.nix`, so `nixos-rebuild switch` updates both system and user environment in one shot.

### Overlays

Four overlays in `flake.nix`, available in every module:
- `pkgs.unstable.*` — nixpkgs unstable
- `pkgs.unfree.*` — stable nixpkgs with `allowUnfree`
- `pkgs.unstable.unfree.*` — unstable + unfree
- `electron_41` pin — see comment in `flake.nix`; unpin when Hydra cache catches up

### Module options

| Option | Layer | Effect |
|--------|-------|--------|
| `head.enable` | system | GDM, PipeWire, Plymouth, gaming |
| `head.gaming` | system | gamemode, gamescope, uinput |
| `desktop.enable` | home | Hyprland, caelestia, apps, comms, office, media |
| `desktop.gaming.enable` | home | Flatpak Steam, Lutris, Prism |
| `desktop.japanese.enable` | home | Japanese fonts/input |
| `programming.enable` | home | Dev tools, Python, R |
| `ai.enable` | home | aichat, aiclip script |
| `ai.claudeCode.enable` | home | claude-code CLI |
| `sync.enable` | home | KDE Connect / Bluetooth |
| `media.enable` | home | media CLI tools |
| `tui.enable` | home | btop, ncmpcpp, ytfzf (default: true) |

### Secrets

`secrets.nix` is git-ignored, injected as a flake input, and available in every module as `secrets`. Expected shape:

```nix
{
  hypr  = { bluetoothHeadsetMac = ""; workEmail = ""; workPassword = ""; workLinkedinUrl = ""; };
  feeds = { ocnewsUrl = ""; ocnewsLogin = ""; };
}
```

Never commit the real file.

### LG Gram hardware

All LG Gram-specific config lives in `hosts/XiaNix/` and is only loaded by that host:
- `hosts/XiaNix/gram.nix` — audio systemd service, input-remapper, iio-hyprland, fcitx5, IME session vars, waydroid sudo rules
- `hosts/XiaNix/lg-gram-audio.sh` — speaker amp init script (referenced by gram.nix)

### Caelestia

Everything caelestia lives under `home/desktop/env/caelestia/`:
- `default.nix` — HM module; enables and configures `programs.caelestia` for any host with `desktop.enable`
- `patches/` — patch overlay applied to caelestia-shell at build time
- `confs/` — live-editable shell.json and shell-tokens.json, symlinked out of store so the control-centre can write to them
- `CAELESTIA.md` — caelestia-specific documentation

### Key module locations

- `home/desktop/env/hyprland.nix` — Hyprland keybinds; uses `secrets.hypr.*`
- `home/term/tui/vim.nix` — Full declarative Nixvim config; all plugins, LSP servers, keymaps, and options live here. No lazy.nvim, no runtime downloads, no mason.
- `home/term/tui/newsboat.nix` — Newsboat; uses `secrets.feeds.*`

---

## Git Commit Guidelines

### When to commit

Commit after every **major change**: adding/removing/rewriting a module, changing flake inputs, migrating a tool, fixing a build error, or adding a significant package. Batch minor tweaks with the surrounding change; don't let unrelated changes accumulate.

### Commit message format

**Match verbosity to the size of the change.**

Small changes (a single alias, a one-line fix, a renamed option) get a single concise sentence — no body needed:
```
restore fixaudio alias to shared zsh config with updated path
```

Large changes (module migrations, architecture refactors, multi-file deletions) get a subject line plus a body covering what changed, why, and any non-obvious details:
```
migrate neovim from AstroNvim+lazy.nvim to nixvim

Replaced confs/nvim/ + symlink approach with a fully declarative nixvim
config in vim.nix. lazy.nvim downloaded plugins at runtime and required
a manual lua/ path fix after every update; nixvim handles all of this at
build time via nix.

- flake.nix: added nix-community/nixvim input
- vim.nix: full rewrite — 20+ plugins, LSP servers via extraPackages,
  all keymaps and options ported
- tui/default.nix: removed programs.neovim.enable
- confs/nvim/: now dead code, deleted
```

### Rules

- **Never** add `Co-Authored-By: Claude` or any AI attribution. Commits represent the owner's work.
- Subject line: imperative, 50 chars or under ("add", "remove", "fix", "migrate" — not "added").
- Body: explain file paths, before/after, and the reason. A future agent should be able to reconstruct what happened and why from the commit message alone.
- No emoji in commit messages.
- Never commit `secrets.nix`, `result`, or `result-*`.
- Never amend published commits — create a new one instead.
