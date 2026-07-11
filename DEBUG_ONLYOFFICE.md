# OnlyOffice Debugging Handoff

## Goal
Get OnlyOffice document editing working in OCIS (ownCloud Infinite Scale) via WOPI.
Currently: clicking a `.docx` file shows a blank/gray editor or "Sorry, editor could not be loaded."

## Architecture
- `cloud.mcgeedan.com` → Caddy → OCIS container at `127.0.0.1:9200` (main) / `127.0.0.1:9300` (collab/WOPI)
- `office.mcgeedan.com` → Caddy → OnlyOffice container at `127.0.0.1:8090`
- All traffic goes through Cloudflare Tunnel → Caddy
- `ocis-collab` sidecar shares OCIS's network namespace (`--network=container:ocis`)
- Both containers are rootful Podman, managed by NixOS `virtualisation.oci-containers`

## What Works (confirmed)
- `POST /app/open` → HTTP 200, returns valid `access_token` in `form_parameters` ✓
- `/app/list` shows OnlyOffice registered for all document types ✓
- ocis-collab is healthy (refreshing service registration every 25s) ✓
- OCIS form-POSTs to OnlyOffice with the access_token in the POST body ✓
- OnlyOffice `CheckFileInfo` → 200 (collab logs confirmed) ✓
- OnlyOffice `SetLock` → 200 / "lock refreshed" (collab logs confirmed) ✓
- All OnlyOffice assets load: nginx access log shows 36 requests, all 200 ✓
- WebSocket upgrade to `wss://office.mcgeedan.com` works at the transport level ✓
- CSP headers on cloud.mcgeedan.com include `office.mcgeedan.com` in `frame-src` and `connect-src` ✓

## What Fails
- No Socket.IO connections to `/doc/{key}/c/` ever appear in OnlyOffice nginx log
- OnlyOffice editor shows blank or "Sorry, editor could not be loaded"
- OCIS web JS throws `RetriableError` in a loop

## Root Cause Identified
The OCIS SSE (Server-Sent Events) endpoint is timing out:

```
XHRGET https://cloud.mcgeedan.com/ocs/v2.php/apps/notifications/api/v1/notifications/sse
[HTTP/2 524  125211ms]
```

**HTTP 524** = Cloudflare killed the connection after ~125 seconds (Cloudflare proxy timeout).

OCIS web's OnlyOffice integration (`web-app-external-XSoeo4XQ.mjs`) does this:
1. OnlyOffice iframe loads → sends `runtimeLoaded` postMessage to OCIS
2. OCIS calls `initializeContext → updateContext → updateAccessTokenPromise`
3. `updateAccessTokenPromise` **waits for `sseAuthenticated` to be true** before sending
   the WOPI context back to the OnlyOffice iframe via postMessage
4. SSE gets 524 → `sseAuthenticated = false` → `RetriableError` thrown
5. OCIS retries with exponential backoff, but SSE keeps getting 524 every ~125s
6. OnlyOffice iframe never receives the postMessage with context → editor stays blank

The retry count grows in the stack trace (`v` called 1x, 2x, 3x... 7x times)
confirming it's stuck in exponential backoff forever.

## Fix Attempted (may or may not have helped)
Added `flush_interval -1` to Caddy's OCIS reverse_proxy in `system/serv/ocis.nix`:
```caddy
flush_interval -1
```
This forces immediate SSE byte flushing so OCIS's keep-alive pings reach Cloudflare
before the ~125s timeout. **Unknown if this fixed the 524 or not — needs verification.**

After the last rebuild the editor now shows "Sorry, editor could not be loaded" instead
of blank/gray. This might be a different error state or a container restart side-effect.

## Immediate Diagnostics to Run

### 1. Check if SSE is still timing out
```bash
# Watch for 524 errors in real time - open a file in OCIS browser while this runs
sudo journalctl -u podman-ocis -f --no-pager | grep -i "sse\|524\|notification"
```

### 2. Check what the OnlyOffice WOPI action page actually returns with a real token
We have a test script. Get a fresh token from the browser (network tab → POST to /app/open
→ response body has `form_parameters.access_token`), then:
```bash
# The script sends a form POST with the token and parses the HTML response
# It checks: statusCode, keyData, fileInfoJsonData, docsApiConfigJsonData
# It also tests Socket.IO polling directly
python3 ~/nixos/test-wopi.py '<action_url>' '<access_token>'
```

The script needs updating — currently it puts the token in the URL query string,
but OCIS sends it in the POST body. Update `post_wopi_action` in `test-wopi.py`:
```python
def post_wopi_action(url, access_token=None, ttl=None):
    params = {}
    if access_token:
        params["access_token"] = access_token
    if ttl:
        params["access_token_ttl"] = ttl
    body = urllib.parse.urlencode(params).encode() if params else b""
    req = urllib.request.Request(url, data=body, method="POST")
    req.add_header("Content-Type", "application/x-www-form-urlencoded")
    ...
```

### 3. Test the WOPI flow directly from inside the OnlyOffice container
```bash
# Get a fresh token from /app/open, then:
sudo podman exec onlyoffice curl -s -X POST \
  'http://127.0.0.1/hosting/wopi/word/edit?WOPISrc=https%3A%2F%2Fcloud.mcgeedan.com%2Fwopi%2Ffiles%2F51d2326f26be1fcaaca8ab956a4af985671f55f2c23e6f6579e0c63e6f3c8534&ui=en-US' \
  -d 'access_token=<TOKEN>&access_token_ttl=<TTL>' \
  -H 'Content-Type: application/x-www-form-urlencoded' | grep -E 'statusCode|keyData|BaseFileName' | head -20
```

### 4. Check OnlyOffice docservice logs
```bash
sudo podman exec onlyoffice cat /var/log/onlyoffice/documentserver/docservice.log | tail -50
sudo podman exec onlyoffice supervisorctl status
```

### 5. Check if SSE is now working (after flush_interval -1 fix)
```bash
# Should hang open and NOT get 524 after ~125s if fix worked
curl -N -H "Authorization: Bearer <ocis-oidc-token>" \
  https://cloud.mcgeedan.com/ocs/v2.php/apps/notifications/api/v1/notifications/sse
```

## Key Files
- `system/serv/ocis.nix` — OCIS container + Caddy vhost (recently added flush_interval -1)
- `system/serv/onlyoffice.nix` — OnlyOffice container + ocis-collab sidecar + Caddy vhost
- `test-wopi.py` — diagnostic script (in repo root)

## Container Debugging Commands
```bash
sudo podman ps -a                          # check all containers running
sudo podman logs podman-ocis-collab        # collab service logs
sudo podman exec onlyoffice supervisorctl status   # docservice health
sudo podman exec onlyoffice cat /var/log/onlyoffice/documentserver/nginx.access.log
sudo podman exec onlyoffice cat /var/log/onlyoffice/documentserver/docservice.log
```

## What to Try If SSE 524 Is Still Happening
If `flush_interval -1` didn't stop the 524s, the options are:

**Option A: Cloudflare dashboard rule**
In Cloudflare dashboard → your zone → Rules → Configuration Rules:
- Match: `http.request.uri.path eq "/ocs/v2.php/apps/notifications/api/v1/notifications/sse"`
  AND hostname matches `cloud.mcgeedan.com`
- Setting: "Proxy Read Timeout" → 600 seconds

**Option B: Check OCIS SSE keep-alive config**
OCIS 8.x might have an env var to control SSE ping interval. Check:
```bash
sudo podman exec ocis env | grep -i "sse\|ping\|keepalive\|notification"
```
If there's an `SSE_PING_INTERVAL` or similar, set it to 30s in `ocis.nix`.

**Option C: Caddy SSE keep-alive injection**
Add a specific handle block in ocis.nix Caddy config for the SSE path that
adds `flush_interval -1` and any needed timeouts.

## What the "Sorry, editor could not be loaded" Message Means
This message is shown by OnlyOffice's WOPI action page JS when `statusCode` is
non-empty in the page HTML. `statusCode` is set by OnlyOffice's server-side
template based on the result of CheckFileInfo. If it's "401", the token was invalid.
If it's another code, something else failed.

The regression from "blank" to "Sorry, error" after the last rebuild might mean:
- The OnlyOffice container restarted and the docservice is in a different state
- OR the flush_interval change affected how the form POST is processed
- OR the file lock from a previous session is causing issues (try a brand new file)

**Try creating a brand new .docx file and opening that** — if an old file has a
stale lock from a previous failed session, it might behave differently.

To clear locks: restart the ocis-collab container:
```bash
sudo systemctl restart podman-ocis-collab
```

## Nix Rebuild Command (on XiaServer)
```bash
sudo HOME=$HOME nixos-rebuild switch --flake $HOME/nixos#XiaServer --impure
```
