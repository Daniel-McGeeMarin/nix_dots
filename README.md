# Nix dots

Personal NixOS and Home Manager configuration, built as a flake. This repo is both my daily-driver setup and a portfolio piece showing declarative system configuration, modular design, and reproducible environments.

---

## What is NixOS?

**NixOS** is a Linux distribution that treats the whole system as code. Instead of editing config files by hand or running install scripts, you declare what you want (packages, services, users, kernel options) in Nix, a purely functional language. A single command (`nixos-rebuild switch`) applies that declaration: the system is built from a single, reproducible specification. Rollbacks are trivial; you can replicate the same setup on another machine or in CI. **Home Manager** extends that idea to your user environment (dotfiles, GUI config, shell, editors) so both OS and “home” are version-controlled and reproducible.

If you’ve used Terraform, Ansible, or Docker Compose, think of NixOS as that same “infrastructure as code” mindset applied to an entire Linux system—with strong reproducibility and a single language (Nix) for packages and config. This repo is a concrete example of that approach: multiple hosts, shared modules, and secrets kept out of version control.

---

## Table of contents

- [What this repo is](#what-this-repo-is)
- [How it works](#how-it-works)
- [Quick start](#quick-start)
- [Repo structure](#repo-structure)
- [The flake](#the-flake)
- [Hosts](#hosts)
- [NixOS modules](#nixos-modules)
- [Home Manager modules](#home-manager-modules)
- [Secrets](#secrets)
- [Credits](#credits)

---

## What this repo is

A **declarative, reproducible** system and user config that demonstrates:

- **NixOS + Home Manager**: Full machine and user-environment definition as Nix; one rebuild updates both.
- **Host-based layout**: Each machine has its own `configuration.nix` and `home.nix` under `hosts/<name>/`, with shared modules to avoid duplication.
- **Modular design**: Reusable NixOS and Home Manager modules (desktop, gaming, TUI tools, media, server stacks) turned on or off via options—easy to adapt for different machines or roles.
- **Secrets handling**: Sensitive values (credentials, device IDs) live in a separate, git-ignored file and are injected via flake input and `specialArgs`; nothing sensitive is committed.
- **Flakes**: Pinned inputs, overlays for multiple nixpkgs versions, and clear entry points (`nixosConfigurations`, `homeConfigurations`) for building and switching.

---

## How it works

1. **Entry point**: `flake.nix` defines `nixosConfigurations.<name>` and optionally `homeConfigurations.<name>`.
2. **System build**: For a host like `XiaNix`, NixOS is built from:
   - Flake `specialArgs` (e.g. `inputs`, `secrets`).
   - A small list of modules in the flake (unfree, overlays).
   - `hosts/XiaNix/configuration.nix`, which pulls in `modules/nixos` and `hosts/XiaNix/hardware-configuration.nix`.
3. **Home Manager**: The same host’s `configuration.nix` sets `home-manager.users."xia" = import ./home.nix`. So the “system” build already includes the home config. `home.nix` imports `modules/home-manager` and passes `inputs` (and optionally the Caelestia shell module). NixOS’s `home-manager.extraSpecialArgs` supplies `inputs`, `pkgs`, and `secrets` to every Home Manager module.
4. **Options**: The shared modules define options (e.g. `head.enable`, `desktop.enable`, `desktop.gaming.enable`, `media.enable`). Host and home configs set these; the modules enable packages and configs conditionally.

So one command (`nixos-rebuild switch --flake .#XiaNix`) updates both system and user environment.

---

## Quick start

- **Build and switch this host** (from repo root):
  ```bash
  sudo nixos-rebuild switch --flake .#XiaNix
  ```
- **Only rebuild home** (if using standalone `homeConfigurations.XiaNix`):
  ```bash
  home-manager switch --flake .#XiaNix
  ```
- **Secrets**: Create a `secrets.nix` (see [Secrets](#secrets)) and point the flake’s `secrets` input at it (e.g. `path:/path/to/secrets.nix`). Do not commit that file.

---

## Repo structure

```
.
├── flake.nix              # Flake inputs, overlays, nixosConfigurations, homeConfigurations
├── flake.lock
├── README.md
├── .gitignore              # e.g. secrets.nix, confs/nvim/.secrets.lua
├── hosts/
│   └── XiaNix/
│       ├── configuration.nix   # Machine-specific NixOS (hostname, hardware, imports)
│       ├── home.nix            # User config for this host (imports HM modules, options)
│       └── hardware-configuration.nix
├── modules/
│   ├── nixos/              # Shared NixOS modules
│   │   ├── default.nix      # Base: HM integration, networking, fonts, extraSpecialArgs
│   │   ├── head/            # Graphical: SDDM, PipeWire, Plymouth, Gram-specific
│   │   ├── serv/            # Optional server: SSH, Home Assistant, media stack
│   │   ├── nvidia.nix
│   │   └── onTheGo.nix      # Specialisation (e.g. laptop power)
│   └── home-manager/        # Shared Home Manager modules
│       ├── default.nix      # Imports desktop, term, rice; nix-flatpak
│       ├── rice.nix         # Theme (nix-colors, GTK, Qt, Flatpak overrides)
│       ├── desktop/         # Apps, env (Hyprland, Waybar, Rofi), gaming, comms, media, office
│       └── term/            # Zsh, TUI (Neovim, Newsboat), programming, AI
├── pkgs/
│   └── sddm-sugar-dark.nix  # Custom/patched SDDM theme
└── confs/                   # External configs (e.g. Neovim) referenced by HM
```

---

## The flake

- **Inputs**: `nixpkgs` (and unstable/master), `home-manager`, Hyprland, nix-colors, Caelestia shell, patched SDDM theme, Firefox CSS hacks, Fcitx5 Gruvbox, etc. **Secrets** are an input (e.g. `path:/path/to/secrets.nix`) so they are not part of the git tree.
- **Overlays**: Unfree and versioned (stable/unstable/master) package sets so you can use `pkgs.unstable.<pkg>` etc.
- **Outputs**:
  - `nixosConfigurations.XiaNix` (and optionally `nixos`) build the full system; they pass `inputs` and `secrets` via `specialArgs`.
  - `homeConfigurations.XiaNix` (and optionally `nixos`) are standalone home-manager builds; they use `extraSpecialArgs = { inputs, secrets }`.
- **System config** for XiaNix is assembled from the flake’s inline module (unfree + overlays) and `hosts/XiaNix/configuration.nix`. Home is inlined via `home-manager.users."xia" = import ./home.nix` and thus uses the same `extraSpecialArgs` as set in `modules/nixos/default.nix`.

---

## Hosts

- **`hosts/XiaNix/`**: Main machine (e.g. laptop). Sets hostname, boot, networking, `head` (graphical + gaming), fonts, timezone, system packages, user and groups, and pulls in `modules/nixos` and `hardware-configuration.nix`. Home is `./home.nix` with desktop, Caelestia, and various toggles (sync, programming, ai, japanese) disabled or enabled.
- **`hosts/XiaNix/home.nix`**: Imports `modules/home-manager` and Caelestia shell; sets `desktop.enable`, `desktop.gaming.enable`, and packages (e.g. Fractal, Calibre, nix-output-monitor). Uses `secrets` where needed (e.g. Hyprland keybinds, Newsboat).
- **`hosts/nixos/`** (if present): Second NixOS config (e.g. server); same pattern with its own `configuration.nix` and `home.nix`.

---

## NixOS modules

- **`modules/nixos/default.nix`**: Core system: Home Manager integration, `extraSpecialArgs` (inputs, pkgs, secrets), systemd-boot, NetworkManager, printing, i18n, RTKit, base packages, nix settings, firewall, font dir. Does not enable display or desktop by itself.
- **`modules/nixos/head/`**: “Headed” (graphical) profile:
  - **`default.nix`**: When `head.enable` is true, enables Plymouth, SDDM, PipeWire; optional `head.gaming` (gamemode, gamescope, uinput).
  - **`sddm.nix`**: SDDM theme (sugar-dark), Wayland, autologin.
  - **`gram.nix`**: LG Gram–specific audio script, firmware, input-remapper, fcitx5, session env (e.g. NIXOS_OZONE_WL).
  - **`plymouth.nix`**, **`grub-theme.nix`**: Boot look.
- **`modules/nixos/serv/`**: Optional server role: SSH, Home Assistant, media stack (Jellyfin, *arr, Deluge, etc.) when `serv.enable` / `serv.media.enable` are set.
- **`modules/nixos/nvidia.nix`**: NVIDIA driver and CUDA (unfree) when included by a host.
- **`modules/nixos/onTheGo.nix`**: Specialisation for laptop (e.g. power, kernel params, disabling Docker/Waydroid).

---

## Home Manager modules

- **`modules/home-manager/default.nix`**: Imports `desktop`, `term`, `rice.nix`, and the nix-flatpak HM module; defines `media.enable`. Receives `secrets` via `extraSpecialArgs` and passes them through.
- **`rice.nix`**: nix-colors (e.g. Gruvbox), GTK/Qt theme and icons, Kvantum, Flatpak global overrides (theme paths), cursor theme.
- **`desktop/`**:
  - **`default.nix`**: Options for `desktop.enable`; pulls in apps, env, gaming, japanese, comms, sync, office, media, gram; default Flatpak apps (Flatseal, MissionCenter, Joplin).
  - **`apps/`**: Browsers (Brave, Librewolf), Foot/Kitty, MPV, Zathura, Bitwarden, PipeWire tools; default apps and MIME.
  - **`env/`**: Hyprland (keybinds, exec-once, waybar, rofi, hypridle, hyprpaper), XDG, GNOME dconf when GNOME is used. Hyprland and Newsboat configs that need secrets receive `secrets` and use e.g. `secrets.hypr.*`, `secrets.feeds.*`.
  - **`gaming.nix`**: Flatpak Steam, Lutris, Prism Launcher, etc., and overrides.
  - **`comms.nix`**, **`sync.nix`**, **`office.nix`**, **`media.nix`**, **`japanese.nix`**: Mail/chat, KDE Connect/Bluetooth, office tools, media tools, Japanese input/fonts.
- **`term/`**: Zsh, TUI (Neovim, Newsboat), programming (Python, R), optional AI (aichat, etc.). Newsboat uses `secrets.feeds` for OCNews URL/login.

---

## Secrets

Sensitive values (Bluetooth MACs, quick-paste strings, feed account identifiers, etc.) are **not** stored in the repo. They live in a separate Nix file and are fed in as a flake input and `specialArgs` / `extraSpecialArgs`.

- **Where**: Create a `secrets.nix` (or any name) **outside** the repo or in a path that is git-ignored (e.g. listed in `.gitignore`). The flake’s `secrets` input should point at it, e.g. `path:/home/user/.config/nixos/secrets.nix` or `path:./secrets.nix` if that path is ignored.
- **Shape**: A Nix attrset. The repo expects at least:
  - **`hypr`**: `bluetoothHeadsetMac`, `workEmail`, `workPassword`, `workLinkedinUrl` (used by Hyprland keybinds).
  - **`feeds`**: `ocnewsUrl`, `ocnewsLogin` (used by Newsboat).
- **Usage**: NixOS and Home Manager receive `secrets` via `specialArgs` / `extraSpecialArgs`. Modules that need it (e.g. Hyprland, Newsboat) take `secrets` as an argument and reference e.g. `secrets.hypr.workEmail`, `secrets.feeds.ocnewsUrl`.
- **Do not commit** the real `secrets.nix` or add it to the flake’s tracked source. Keep it local and point the flake input at its absolute path if necessary.

Example skeleton (adapt and keep local):

```nix
{
  hypr = {
    bluetoothHeadsetMac = "00:11:22:33:44:55";
    workEmail          = "you@example.com";
    workPassword       = "change-me";
    workLinkedinUrl    = "https://www.linkedin.com/in/your-handle/";
  };

  feeds = {
    ocnewsUrl   = "https://your-cloud.example.com";
    ocnewsLogin = "your-login";
  };
}
```

---

## Graphide API service

`system/serv/graphide.nix` runs the Graphide cloud API server on XiaServer as three Podman containers (PostgreSQL, Redis, Go API) on host networking, proxied by Caddy at `graphideapi.mcgeedan.com`.

Enable with `serv.graphide.enable = true` in the host's `configuration.nix`.

**Two secrets required** (agenix-encrypted, in `secrets/`):

| File | Contents |
|---|---|
| `graphide-api-env.age` | `POSTGRES_USER`, `POSTGRES_DB`, `POSTGRES_PASSWORD`, `DATABASE_URL`, `REDIS_URL`, `SUPABASE_URL`, `ANTHROPIC_API_KEY`, `PORT` |
| `ghcr-token.age` | GitHub PAT with `read:packages` scope (pulls the private GHCR image) |

The container image (`ghcr.io/graphidehq/monolith-api:latest`) is built and pushed automatically by the deploy workflow in the [monolith repo](https://github.com/GraphideHQ/monolith) on every push to `master`.

Full setup instructions and gotchas (postgres UID, startup sequencing) are documented at the top of `system/serv/graphide.nix`.

**Verify the service is healthy:**
```sh
curl http://localhost:8080/health   # {"status":"ok"}
curl http://localhost:8080/ready    # {"status":"ok"} — confirms DB + Redis up
```

---

## Credits

Thanks to **Ben** for helping build and refine this repo and the Nix setup over time.
