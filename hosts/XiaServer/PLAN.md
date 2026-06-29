# XiaServer — Home Server Build Plan

## Goal

Fully declarative NixOS home server, open to the internet via a custom domain. All services managed
by the flake — rebuilding on a new machine restores everything except raw data files. Adding a new
webapp is a Nix config change + container image; no manual server work.

---

## Stack

| Layer | Tool | Rationale |
|---|---|---|
| Ingress | Cloudflare Tunnel (`cloudflared`) | No open ports, hides home IP, free DDoS protection |
| Reverse proxy | Caddy | Auto HTTPS/Let's Encrypt, clean config, NixOS module |
| Auth middleware | Authelia | SSO in front of all services, single login for the whole server |
| Secrets | agenix | Encrypted in git with host SSH key, decrypted to `/run/agenix/` (tmpfs) at boot |
| Containers | Podman via `virtualisation.oci-containers` | Rootless, declarative, OCI-compatible — replaces Docker |
| Persistent data | `/srv/data/<service>/` on 1TB data drive | Lives outside containers; survives rebuilds and image updates |

### Docker → Podman migration note

`configuration.nix` currently enables `virtualisation.docker`. Once Podman covers all services,
remove `virtualisation.docker` and the `docker` group from the XiaServer user.

---

## Storage architecture

### Current hardware

- **256GB SSD** — NixOS root (`/`): OS, Nix store, container images, service config. Already
  LUKS-encrypted (declared in `hardware-configuration.nix`).
- **1TB HDD** — Data (`/srv/`): all persistent service data, user files, backups. Not yet declared
  in NixOS — requires one-time setup below.

The OS drive can be wiped and rebuilt from the flake. Only the data drive needs to be preserved.

### Filesystem: ZFS with native encryption

ZFS native encryption — **not** LUKS under ZFS. Reasons:
- One layer manages both storage and encryption; LUKS underneath adds complexity for no gain
- `zfs send` works correctly with native encryption for encrypted cloud backup; LUKS-on-ZFS breaks
  incremental sends
- Per-dataset encryption policies possible in the future
- Adding drives later is a single command; no repartitioning ever needed

### Disk layout — full drive, no partitioning

ZFS does not pre-allocate space. Use the full 1TB for one pool; datasets grow as data is added.
Windows backup files get their own dataset (`data/windows-import`) — no need to leave space
unformatted. All 1TB is addressable from day one.

**One-time setup on the physical server** (shell commands run once, then managed by Nix forever):

```bash
# Identify the 1TB drive — verify before running
lsblk

# Create encrypted ZFS pool on the full drive
# Use /dev/disk/by-id/ — survives drive bay changes
zpool create \
  -O encryption=aes-256-gcm \
  -O keyformat=raw \
  -O keylocation=file:///run/agenix/zfs-data-key \
  -O compression=lz4 \
  -O atime=off \
  -O xattr=sa \
  data /dev/disk/by-id/ata-YOUR_DRIVE_ID

# Create datasets
zfs create data/srv
zfs create data/srv/data
zfs create data/srv/www
zfs create data/windows-import   # staging area for Windows backup migration
```

### Encryption key management

The pool key is a 32-byte random file managed by agenix:

```
secrets/zfs-data-key.age   ← random binary key, encrypted with host SSH key, committed to git
  → agenix decrypts to /run/agenix/zfs-data-key at boot (tmpfs, never touches disk unencrypted)
  → systemd unit runs: zfs load-key data && zfs mount -a
  → /srv becomes available
  → container services start (After= the ZFS mount unit)
```

The server reboots fully unattended — no passphrase prompt required.
Loss of the key = loss of pool access. The key is in git (encrypted) — that IS the backup of it.

### NixOS declaration

Goes in a new `storage.nix` (not `hardware-configuration.nix`, which is auto-generated):

```nix
# hosts/XiaServer/storage.nix
{ config, ... }:
{
  boot.supportedFilesystems = [ "zfs" ];
  boot.zfs.extraPools = [ "data" ];

  fileSystems."/srv" = {
    device = "data/srv";
    fsType = "zfs";
  };

  systemd.tmpfiles.rules = [
    "d /srv/data              0755 root root"
    "d /srv/data/authelia     0750 authelia authelia"
    "d /srv/data/homarr       0750 root root"
    "d /srv/data/ghost-public 0750 root root"
    "d /srv/data/ghost-private 0750 root root"
    "d /srv/www               0755 root root"
  ];
}
```

### Data layout

```
ZFS pool "data"
  data/srv              → mounted at /srv
    /srv/data/
      authelia/         # Authelia user DB, TOTP secrets
      homarr/           # dashboard config
      ghost-public/     # public blog: posts, images, SQLite DB
      ghost-private/    # private blog: posts, images, SQLite DB
      ocis/             # OCIS user files (deferred)
    /srv/www/
      demo/             # built React demo app static files
  data/windows-import   → mounted at /mnt/windows-import (staging, not under /srv)
```

### Future multi-drive expansion

```bash
zpool add data /dev/disk/by-id/ata-NEW_DRIVE_ID   # stripe (more space)
# or
zpool attach data existing-drive new-drive          # mirror (redundancy)
```

No Nix config change needed for existing services. New drives are immediately usable.

---

## Encrypted cloud backup (planned, not immediate)

```
zfs snapshot data/srv@YYYYMMDD
  → zfs send -i (incremental — only changes since last snapshot)
  → age encrypt (client-side; cloud provider sees only ciphertext)
  → rclone upload to Backblaze B2
```

Implemented as a systemd timer in a future `backup.nix` module.
**Backup target**: Backblaze B2 — $6/TB/month, S3-compatible, rclone native support.
The ZFS choice is made now specifically to make this trivial later.

---

## Phase 1 services (what we are building now)

### 1. Dashboard — Homarr

- **Image**: `ghcr.io/ajnart/homarr:latest` (Podman)
- **Purpose**: Unified launcher and status overview for all self-hosted services
- **Auth**: Behind Authelia — require login
- **Data**: `/srv/data/homarr/`
- **Domain**: `dash.yourdomain.com`

### 2. Public blog — Ghost

- **Image**: `ghost:5-alpine` (Podman)
- **Purpose**: Public-facing blog; anyone can read, you write from `/ghost` admin panel
- **Auth**: Ghost admin path (`/ghost`) behind Authelia; public posts fully open
- **Data**: `/srv/data/ghost-public/content/`
- **DB**: SQLite (Ghost default)
- **Domain**: `blog.yourdomain.com`

### 3. Private blog — Ghost (second instance)

- **Image**: `ghost:5-alpine` (Podman, separate container, different port)
- **Purpose**: Blog for friends and family; Ghost's native membership system gates all content —
  readers sign up, you approve them manually in the Ghost admin panel
- **Auth**: Ghost membership gates content; Authelia guards the `/ghost` admin path
- **Data**: `/srv/data/ghost-private/content/`
- **DB**: SQLite
- **Domain**: `journal.yourdomain.com`

### 4. Demo React webapp

- **Purpose**: Validates the full CI → Podman → Caddy deploy pipeline; template for all future
  custom webapps (poker games, tools, etc.)
- **Stack**: Vite + React, served via nginx:alpine container
- **CI**: GitHub Actions builds image → pushes to GHCR → server pulls on timer (pull-based)
- **Domain**: `demo.yourdomain.com`
- **Auth**: None for now

---

## Deferred services (later phases)

- **OCIS + ONLYOFFICE** — file storage and in-browser office editing
- **Additional webapps** — each follows the same pattern as the demo

---

## Module structure

Inherited dead-code modules (`home-assistant.nix`, `media.nix`, `minecraft.nix`, `wireguard.nix`)
are removed — they were never enabled and came from the upstream fork.

```
system/serv/
  default.nix     # base SSH config + imports
  network.nix     # Caddy + cloudflared
  auth.nix        # Authelia
  dashboard.nix   # Homarr
  blogs.nix       # both Ghost instances
  apps.nix        # custom webapps (demo + future)
```

Enabled in `configuration.nix`:

```nix
serv = {
  enable           = true;
  network.enable   = true;
  auth.enable      = true;
  dashboard.enable = true;
  blogs.enable     = true;
  apps.demo.enable = true;
};
```

Adding a new webapp later:

```nix
# apps.nix — add one block:
options.serv.apps.poker.enable = lib.mkEnableOption "Poker webapp";
config = lib.mkIf config.serv.apps.poker.enable {
  virtualisation.oci-containers.containers.poker = {
    image  = "ghcr.io/youruser/poker:latest";
    ports  = [ "127.0.0.1:3002:3000" ];
    labels."io.containers.autoupdate" = "registry";
  };
};
# Then: serv.apps.poker.enable = true; → nixos-rebuild switch → live
```

---

## Deploy model — pull-based, GitHub has zero server access

GitHub Actions pushes images to GHCR only. No SSH key, no server access.

```
you push code
  → Actions: build image → push ghcr.io/youruser/app:latest + :sha-abc1234
  → GitHub's involvement ends here

server (systemd timer, every 5 min)
  → podman auto-update checks GHCR for new image digest
  → pulls and restarts changed containers
  → new version is live
```

Blast radius of a compromised GitHub: one container gets a bad image. Host, secrets, other
services, and data are untouched. Each container only receives the specific agenix secret it needs.

```nix
labels."io.containers.autoupdate" = "registry";   # on each app container

systemd.timers.podman-auto-update = {
  wantedBy     = [ "timers.target" ];
  timerConfig.OnCalendar = "*:0/5";
};
```

---

## Secrets

| Secret file | Used by | Notes |
|---|---|---|
| `zfs-data-key.age` | ZFS pool unlock | 32-byte random key; loss = data loss |
| `cloudflare-tunnel.age` | cloudflared | Tunnel credentials JSON |
| `authelia-jwt.age` | Authelia | JWT signing secret |
| `authelia-session.age` | Authelia | Session encryption secret |
| `authelia-storage.age` | Authelia | Storage encryption key |
| `ghost-public-env.age` | Ghost (public) | url, admin config |
| `ghost-private-env.age` | Ghost (private) | url, admin config |

---

## Network routing

```
yourdomain.com          → Caddy: demo React app (placeholder until main site exists)
dash.yourdomain.com     → Caddy: Authelia → Homarr :3000
blog.yourdomain.com     → Caddy: Ghost public :2368 (public; admin behind Authelia)
journal.yourdomain.com  → Caddy: Ghost private :2369 (Ghost membership gates content)
demo.yourdomain.com     → Caddy: React demo :3001
```

Authelia on `localhost:9091`. `forward_auth` snippet defined once in Caddy, reused per host.

---

## Implementation order

1. **Cleanup** — remove inherited dead-code modules; rebuild to confirm nothing breaks
2. **Storage** — run `zpool create` on server, add `storage.nix`, generate ZFS key secret
3. **agenix** — add to flake, `secrets.nix`, verify `/run/agenix/` decryption at boot
4. **Caddy + cloudflared** (`network.nix`) — placeholder page live at domain over HTTPS
5. **Authelia** (`auth.nix`) — SSO working, login flow tested
6. **Homarr** (`dashboard.nix`) — first container, validates full Podman + Authelia path
7. **Ghost public** (`blogs.nix`) — public blog live
8. **Ghost private** — second instance, test membership gating
9. **React demo** (`apps.nix`) — hello-world app, full CI pipeline, confirm auto-update works
10. **Backup** — ZFS snapshot timer + encrypted upload (any time after step 2)

---

## Portability guarantee

To migrate to new hardware:
1. `zfs send data/srv | ssh newserver zfs receive data/srv`
2. Copy or re-encrypt agenix secrets for the new host key
3. `nixos-rebuild switch --flake .#XiaServer`
4. Services come back up pointing to the same data

No manual config. No remembered state outside `/srv/` and git.
