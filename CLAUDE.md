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

### Flake structure

`flake.nix` defines two hosts:
- **XiaNix** — main desktop (LG Gram laptop)
- **nixos** — server (`phantomServ`)

Each host has `nixosConfigurations.<name>` and `homeConfigurations.<name>`. The NixOS build at `hosts/XiaNix/configuration.nix` already inlines Home Manager via `home-manager.users."xia" = import ./home.nix`, so `nixos-rebuild switch` updates both system and user environment in one shot. The `homeConfigurations` output is a standalone alternative.

### Overlays

Four overlays are wired up in `flake.nix` and passed to every NixOS and Home Manager module:
- `pkgs.unstable.*` — nixpkgs unstable
- `pkgs.unfree.*` — stable nixpkgs with `allowUnfree`
- `pkgs.unstable.unfree.*` — unstable + unfree
- `electron_41` pin — see the comment in `flake.nix`; unpin when the Hydra cache catch up

### Module options

The shared modules expose boolean options that hosts toggle:

| Option | Where set | Effect |
|--------|-----------|--------|
| `head.enable` | NixOS module | SDDM, PipeWire, Plymouth |
| `head.gaming` | NixOS module | gamemode, gamescope, uinput |
| `desktop.enable` | HM module | Hyprland env, apps, comms, office, media |
| `desktop.gaming.enable` | HM module | Flatpak Steam, Lutris, Prism |
| `desktop.japanese.enable` | HM module | Japanese fonts/input |
| `programming.enable` | HM module | Dev tools, Python, R |
| `ai.enable` | HM module | aichat, aiclip script |
| `ai.claudeCode.enable` | HM module | claude-code CLI |
| `sync.enable` | HM module | KDE Connect / Bluetooth |
| `media.enable` | HM module | media CLI tools |
| `tui.enable` | HM module | btop, ncmpcpp, ytfzf (default: true) |

### Secrets

`secrets.nix` is git-ignored and injected as a flake input (`path:./secrets.nix`). It flows through `specialArgs`/`extraSpecialArgs` as `secrets` and is available in every module. Expected shape:

```nix
{
  hypr  = { bluetoothHeadsetMac = ""; workEmail = ""; workPassword = ""; workLinkedinUrl = ""; };
  feeds = { ocnewsUrl = ""; ocnewsLogin = ""; };
}
```

Modules that consume secrets take it as a function argument (e.g. `{ secrets, ... }:`). Never commit the real file.

### Caelestia shell patches

`caelestiapatches/` is a small Nix overlay that applies local `.patch` files to the upstream `caelestia-shell` package before it builds. To add a patch: generate a unified diff, drop it in the directory, and list it in `caelestiapatches/default.nix`. The patched package is instantiated in `hosts/XiaNix/home.nix` and passed to `programs.caelestia.package`.

### Key module locations

- `modules/nixos/head/gram.nix` — LG Gram hardware quirks (audio script, fcitx5, input-remapper, session env vars)
- `modules/home-manager/desktop/env/hyprland.nix` — Hyprland keybinds; uses `secrets.hypr.*`
- `modules/home-manager/term/tui/vim.nix` — Full declarative Nixvim config; all plugins, LSP servers, keymaps, and options live here. No lazy.nvim, no runtime downloads, no mason. Plugins are from nixpkgs `vimPlugins` or built via `buildVimPlugin` (caelestia-nvim has a lua/ path fix applied at build time).
- `modules/home-manager/term/tui/newsboat.nix` — Newsboat; uses `secrets.feeds.*`
- `confs/nvim/` — **archived / dead code** after the nixvim migration. Previously the AstroNvim + lazy.nvim config, now superseded by `vim.nix`. Safe to delete once verified.
- `confs/caelestia/shell.json` — Caelestia shell settings, symlinked into `~/.config/caelestia/` via an out-of-store symlink so the control-centre can write to it live.

---

## Git Commit Guidelines

These rules apply to all commits in this repository. AI assistants working here must follow them exactly.

### When to commit

Commit after every **major change** to the codebase. A major change is anything that:
- Adds, removes, or substantially rewrites a module (NixOS or Home Manager)
- Changes `flake.nix` inputs or overlays
- Migrates a tool or workflow to a new approach (e.g. AstroNvim → Nixvim)
- Fixes a build error or system breakage
- Adds or updates a significant package or service

Minor reformats or one-line tweaks can be batched with the surrounding change. Do not let unrelated changes accumulate across multiple features — keep commits focused.

### Commit message format

Use a short **imperative subject line** (50 chars or under), then a **blank line**, then a **detailed body** explaining:

1. **What** was changed and in which files/modules
2. **Why** — the motivation or problem being solved
3. **How** — any non-obvious implementation details, trade-offs, or workarounds
4. **Side effects** — anything else that changes as a result (e.g. a file becoming dead code, a dependency being dropped)

Example of a good commit:

```
migrate neovim from AstroNvim+lazy.nvim to nixvim

Replaced the AstroNvim/lazy.nvim setup (confs/nvim/ + vim.nix symlink
approach) with a fully declarative nixvim configuration in vim.nix.

Why: lazy.nvim downloaded plugins at runtime and required a manual
directory fix for caelestia-nvim (lua/ path issue) after every install
or update. Nixvim fetches all plugins through nix, applies the caelestia
path fix at build time, and provides LSP servers via nix packages instead
of mason.

Changes:
- flake.nix: added nix-community/nixvim input (nixos-25.11 branch)
- vim.nix: full rewrite — programs.nixvim replaces programs.neovim;
  20+ plugins declared declaratively; LSP servers (lua_ls, clangd,
  rust-analyzer, pyright, nixd) provided via extraPackages; all
  VS Code-style keymaps, VimTeX autocmds, and polish.lua options
  ported to nix
- tui/default.nix: removed programs.neovim.enable (nixvim manages it)
- confs/nvim/: now dead code; safe to delete after verification
```

### Rules

- **Never** add `Co-Authored-By: Claude` or any AI attribution to commit messages. Commits represent the owner's work.
- Write messages as if explaining to a future developer (human or AI) who has no context — include file paths, before/after descriptions, and the reason for the change.
- Use the present tense imperative for the subject line: "add", "remove", "fix", "migrate", "update" — not "added" or "adding".
- Do not use emoji in commit messages.
- Do not commit `secrets.nix`, `result`, or `result-*` (these are gitignored).
- Do not amend published commits (commits already pushed to origin/main). Create a new commit instead.
