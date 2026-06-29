# XiaServer — Home Server Build Plan

## Goal

Fully declarative NixOS home server, open to the internet via a custom domain. All services managed
by the flake — rebuilding on a new machine should restore everything except raw data files.

---

## Stack

| Layer | Tool | Rationale |
|---|---|---|
| Ingress | Cloudflare Tunnel (`cloudflared`) | No open ports, hides home IP, free DDoS protection |
| Reverse proxy | Caddy | Auto HTTPS/Let's Encrypt, clean config, NixOS module |
| Auth middleware | Authelia | SSO in front of all services, single login for the whole server |
| Secrets | agenix | Encrypted in git with host SSH key, decrypted to `/run/agenix/` (tmpfs) at boot |
| Containers | Podman via `virtualisation.oci-containers` | Rootless, declarative, OCI-compatible — replaces current Docker setup |
| Persistent data | `/srv/data/<service>/` bind mounts | Lives outside containers; survives rebuilds and image updates |

### Docker → Podman migration note

`configuration.nix` currently enables `virtualisation.docker`. Once Podman covers all services,
remove `virtualisation.docker` and the `docker` group from the XiaServer user. Existing services
(Jellyfin, Prowlarr, etc.) are NixOS-native and unaffected.

---

## Services

### 1. Dashboard — Homarr

- **Image**: `ghcr.io/ajnart/homarr:latest` (Podman)
- **Purpose**: Unified launcher and status overview for all self-hosted services
- **Auth**: Behind Authelia — require login
- **Data**: `/srv/data/homarr/` for config (bookmarks, layout, icon cache)
- **NixOS prior art**: `virtualisation.oci-containers.containers.homarr` pattern, straightforward
- **Notes**: Configured via its web UI; config persists in the bind mount

### 2. Public website

- **Approach**: Static files served directly by Caddy — no container needed
- **Build**: Hugo or Astro site, output committed to repo or built as a Nix derivation and served
  from the store path
- **Auth**: None — fully public
- **Domain**: `yourdomain.com` / `www.yourdomain.com`
- **Notes**: Caddy's `file_server` directive handles this in a single block; no extra process

### 3. Blog — Ghost

- **Image**: `ghost:5-alpine` (Podman)
- **Purpose**: Personal blog for friends and family; Ghost's native membership/subscription system
  gates content (readers register with email, you approve) — no need for Authelia here
- **Auth**: Ghost membership for content access; Authelia guards `/ghost` admin path
- **Data**: `/srv/data/ghost/content/` bind mount (themes, images, database)
- **DB**: SQLite (Ghost default) — adequate for personal traffic, zero extra containers
- **Domain**: `blog.yourdomain.com`
- **NixOS prior art**: Well-documented `oci-containers` setup; Ghost's official Docker image is
  production-quality

### 4. ownCloud Infinite Scale (OCIS)

- **Image**: `owncloud/ocis:latest` (Podman)
- **Purpose**: File storage and sync (replaces Nextcloud; lighter, faster)
- **Auth**: OCIS ships its own IdP (LibreGraph); Authelia sits in front at the Caddy layer for the
  web UI; sync clients authenticate directly to OCIS
- **Data**: `/srv/data/ocis/` bind mount — this is the big one, all user files live here
- **Domain**: `cloud.yourdomain.com`
- **NixOS prior art**: No official NixOS module; `oci-containers` is the right path. The
  [owncloud/ocis Docker docs](https://doc.owncloud.com/ocis/next/deployment/container/container-setup.html)
  provide a well-maintained reference `docker-compose.yml` that maps cleanly to `oci-containers`
  options
- **Notes**: OCIS requires several env vars (admin password, JWT secret, etc.) — all via agenix
  env file

### 5. Office editor — ONLYOFFICE Document Server

- **Image**: `onlyoffice/documentserver:latest` (Podman)
- **Purpose**: In-browser editing of `.docx`, `.xlsx`, `.pptx` files — integrated with OCIS
- **Why ONLYOFFICE over Collabora**: ONLYOFFICE is React/Node-based; Collabora is LibreOffice
  wrapped in a browser — significantly slower. ONLYOFFICE is the recommended choice when snappiness
  matters and the user has had bad experiences with Collabora's latency
- **Integration**: OCIS has a built-in ONLYOFFICE app that uses the WOPI protocol. Both services
  share a JWT secret for secure API communication
- **Auth**: Not directly exposed; traffic comes only from OCIS app provider calls. Caddy proxies
  `office.yourdomain.com` but only OCIS backend talks to it — no user-facing login needed here
- **Data**: Stateless (no persistent data needed beyond the JWT secret)
- **NixOS prior art**: Official Docker image; OCIS ↔ ONLYOFFICE integration is well-documented by
  ownCloud

---

## Module structure

New modules live in `system/serv/` following the existing pattern:

```
system/serv/
  default.nix          # existing — add imports for new modules
  home-assistant.nix   # existing
  media.nix            # existing
  minecraft.nix        # existing
  wireguard.nix        # existing
  network.nix          # NEW: Caddy + cloudflared — the ingress layer
  auth.nix             # NEW: Authelia
  dashboard.nix        # NEW: Homarr
  website.nix          # NEW: static site via Caddy file_server
  blog.nix             # NEW: Ghost container
  ocis.nix             # NEW: OCIS + ONLYOFFICE (tightly coupled, one file)
```

Each new module exposes an option:

```nix
options.serv.network.enable   = lib.mkEnableOption "Caddy + Cloudflare Tunnel";
options.serv.auth.enable      = lib.mkEnableOption "Authelia SSO";
options.serv.dashboard.enable = lib.mkEnableOption "Homarr dashboard";
options.serv.website.enable   = lib.mkEnableOption "Public static website";
options.serv.blog.enable      = lib.mkEnableOption "Ghost blog";
options.serv.ocis.enable      = lib.mkEnableOption "OCIS + ONLYOFFICE";
```

Enabled in `hosts/XiaServer/configuration.nix`:

```nix
serv = {
  enable        = true;
  network.enable   = true;
  auth.enable      = true;
  dashboard.enable = true;
  website.enable   = true;
  blog.enable      = true;
  ocis.enable      = true;
};
```

---

## Secrets

All secrets live in `secrets/` as `.age` files, encrypted with XiaServer's SSH host public key.
Decrypted paths are referenced via `config.age.secrets.<name>.path`.

| Secret file | Used by | Notes |
|---|---|---|
| `cloudflare-tunnel.age` | cloudflared | Tunnel credentials JSON from Cloudflare dashboard |
| `authelia-jwt.age` | Authelia | JWT signing secret (random 64-char string) |
| `authelia-session.age` | Authelia | Session encryption secret |
| `authelia-storage.age` | Authelia | Storage encryption key |
| `ocis-env.age` | OCIS | Admin password, JWT secret, OCIS_URL, etc. as env file |
| `onlyoffice-jwt.age` | ONLYOFFICE + OCIS | Shared JWT secret for WOPI API trust |
| `ghost-env.age` | Ghost | `url`, `mail__*` settings if email configured |

agenix setup: add `github:ryantm/agenix` to `flake.nix` inputs, add the agenix NixOS module to
XiaServer's imports, add `secrets.nix` at the repo root defining which host key decrypts which file.

---

## Network routing

Cloudflare Tunnel receives all traffic and hands it to Caddy on localhost. Caddy routes by hostname.

```
yourdomain.com          → Caddy: file_server /srv/www/site/   (no auth)
blog.yourdomain.com     → Caddy: reverse_proxy localhost:2368  (Ghost, no Authelia — Ghost gates internally)
dash.yourdomain.com     → Caddy: Authelia forward_auth → reverse_proxy localhost:3000 (Homarr)
cloud.yourdomain.com    → Caddy: Authelia forward_auth → reverse_proxy localhost:9200 (OCIS web)
office.yourdomain.com   → Caddy: reverse_proxy localhost:8080 (ONLYOFFICE, OCIS-internal only)
```

Authelia runs on `localhost:9091`. Caddy's `forward_auth` snippet is defined once and reused across
all protected hosts.

---

## Data layout and portability

```
/srv/data/
  homarr/          # dashboard config
  ghost/content/   # blog posts, images, DB (sqlite)
  ocis/            # ALL user files — largest volume, back this up
  authelia/        # user DB, TOTP secrets
/srv/www/
  site/            # static website files (or symlink to Nix store derivation output)
```

To migrate to new hardware:
1. `rsync -av /srv/ newserver:/srv/` (data)
2. Re-encrypt agenix secrets with new host key OR copy old host key to new server
3. `nixos-rebuild switch --flake .#XiaServer` on new server
4. Everything comes back up — no manual service config

---

## Implementation order

Build in this sequence so each layer can be tested before adding the next:

1. **agenix** — add to flake, set up `secrets.nix`, create first secret, verify decryption at boot
2. **Caddy + cloudflared** (`network.nix`) — get a test page live at your domain with HTTPS working
3. **Authelia** (`auth.nix`) — wire up SSO, verify login flow with Caddy forward_auth
4. **Homarr** (`dashboard.nix`) — first container behind Authelia, validates the full Podman + auth pattern
5. **Static website** (`website.nix`) — Caddy file_server, public, no auth
6. **Ghost** (`blog.nix`) — container, verify membership gating works
7. **OCIS** (`ocis.nix`) — file storage, test desktop sync client
8. **ONLYOFFICE** (same file as OCIS) — connect to OCIS, test opening and editing a document

Each step is independently testable and independently revertable.

---

## Open questions / decisions to make before implementing

- **Domain structure**: confirm subdomains (`cloud.`, `blog.`, etc.) vs. paths (`yourdomain.com/cloud`)
  — subdomains are strongly preferred, easier to route and cert
- **Website tech**: Hugo, Astro, or raw HTML? If Hugo/Astro, build in CI or as a Nix derivation?
- **Ghost email**: do you want Ghost to send membership confirmation emails? Requires SMTP config
  (Mailgun/Resend work well with Ghost, free tiers are fine)
- **OCIS storage backend**: default local FS on `/srv/data/ocis/` is fine to start; can add S3
  backend later if you want offsite object storage
- **Authelia user store**: file-based (a single YAML of users) is simplest for a personal server;
  LDAP is overkill here
