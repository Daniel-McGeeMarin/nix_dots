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
| `desktop.workmic.enable` | home | Push-to-talk mic gating (SUPER+SPACE) |
| `desktop.japanese.enable` | home | Japanese fonts/input |
| `programming.enable` | home | Dev tools, Python, R |
| `ai.enable` | home | aichat, aiclip script |
| `ai.claudeCode.enable` | home | claude-code CLI |
| `sync.enable` | home | KDE Connect / Bluetooth |
| `media.enable` | home | media CLI tools |
| `tui.enable` | home | btop, ncmpcpp, ytfzf (default: true) |

### Adding a package

A plain package with no options, service, or extra config (dotfiles, wrapper scripts, systemd units, etc.) does **not** get its own `.nix` file — add it to the `home.packages` list in the relevant `default.nix` instead:
- Desktop GUI apps → `home/desktop/default.nix` (see the "Browsers & editors" section, e.g. `vscodium`, `unfree.code-cursor`)
- CLI dev tools → `home/term/modules/programming/default.nix`
- General CLI tools → `home/term/default.nix`

Only give a package its own file under `apps/`, `modules/`, or similar when it needs real config — a wrapper derivation (unpackaged upstream, e.g. an AppImage like `orca.nix`), non-trivial `programs.*`/`services.*` settings, or its own enable option.

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

## XiaServer container patterns

Hard-won lessons from deploying services. Check these before debugging.

### Caddy on Cloudflare Tunnel

- **Never use `localhost`** in Caddy virtual host configs — Caddy resolves it to `::1` (IPv6) but most services only bind to `127.0.0.1`. Always use `127.0.0.1` explicitly.
- **Always add `header_up X-Forwarded-Proto https`** in any `reverse_proxy` block for a TLS-aware app. Cloudflare terminates TLS; Caddy receives plain HTTP and must tell the upstream the original scheme was HTTPS. Without this, apps like Authelia and OCIS generate `http://` redirect URLs that they then reject.
- The `(require_auth)` Caddy snippet already includes this header for Authelia `forward_auth`. Add it separately to individual `reverse_proxy` blocks for the backend services themselves.

### Podman / oci-containers

- **All `podman` management commands require `sudo`** — the systemd services run as root (rootful Podman). `podman ps -a` without sudo shows the user's rootless containers only.
- **Always use fully-qualified image names** in any container that has `io.containers.autoupdate = registry`. Podman refuses short names for auto-update: `docker.io/library/ghost:5-alpine` not `ghost:5-alpine`, `docker.io/owncloud/ocis:latest` not `owncloud/ocis:latest`.
- **Container-to-container networking via DNS works** (Podman default network with `dns_enabled = true` resolves container names), but services inside containers often bind to `127.0.0.1` by default, making them unreachable from other containers even though DNS resolves. To debug: `sudo podman exec <name> cat /proc/net/tcp | grep <hex-port>` — `0100007F` means `127.0.0.1` (loopback only), `00000000` means `0.0.0.0` (all interfaces).
- **Sidecar pattern**: when a sidecar container needs to share `localhost` with a main container, use `extraOptions = [ "--network=container:<name>" ]`. The sidecar then shares the main container's full network namespace including loopback, Podman network IP, and all listening ports.
- **Data directory ownership**: check what UID the container process runs as (`podman inspect` or docs) and set `systemd.tmpfiles.rules` accordingly. OCIS runs as UID 1000; Ghost runs as root.
- **Env file changes don't restart containers**: NixOS only restarts a container when its *path* changes, not when file *content* changes. After updating a secret in an `.age` file, run `systemctl restart podman-<name>` manually.

### Debugging failing containers

Standard sequence:
1. `sudo podman ps -a` — is it running or exiting?
2. `sudo journalctl -u podman-<name> --no-pager | grep fatal | tail -3` — get the full error (journald truncates long lines; use `--no-pager` and grep)
3. If the container exits too fast to log: `sudo systemctl reset-failed podman-<name>; sudo systemctl start podman-<name>; sudo journalctl -u podman-<name> --since "30 seconds ago" --no-pager`
4. If the error is truncated even then: run the container manually with `sudo podman run --rm -e VAR=val ... image command 2>&1 | head -30`

### agenix / secrets

- **Server rebuild command**: `sudo HOME=$HOME nixos-rebuild switch --flake $HOME/nixos#XiaServer --impure` — the `--impure` is required because `secrets.nix` is loaded via `builtins.getEnv "HOME"`.
- **Encrypt a new secret on the server**: `PUBKEY=$(awk '{print $1" "$2}' /etc/ssh/ssh_host_ed25519_key.pub)` then pipe content to `nix run nixpkgs#age -- -r "$PUBKEY" -o secrets/name.age`.
- **Generating random hex without openssl**: `od -A n -t x1 -N 32 /dev/urandom | tr -d ' \n'` (32 bytes = 64 hex chars).

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
