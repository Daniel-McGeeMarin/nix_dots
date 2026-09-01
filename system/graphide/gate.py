"""Invite-only gate in front of the Graphide demo boxes.

A signed URL logs the guest in and binds them to exactly one box. Caddy
asks /api/demo/authz on every request; without a valid cookie the pod is
never reached. See system/graphide/gate.nix for how this is wired.
"""

import argparse
import base64
import hashlib
import hmac
import json
import os
import secrets
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse


COOKIE = "graphide_demo"
STATE_LOCK = threading.Lock()
CONTACT = "hello@graphide.net"


def splash(title: str, heading: str, body: str) -> str:
    return f"""<!doctype html>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{title}</title>
<style>
  :root {{ color-scheme: dark; }}
  body {{ font: 16px/1.5 system-ui, sans-serif; max-width: 28em; margin: 22vh auto; padding: 0 1.5rem; color: #e8e8e8; background: #111; }}
  h1 {{ font-size: 1.35rem; font-weight: 600; margin: 0 0 .8rem; }}
  p {{ color: #b5b5b5; margin: 0 0 .85rem; }}
  a {{ color: #8cb4ff; }}
  .contact {{ margin-top: 1.6rem; font-size: .95rem; }}
</style>
<h1>{heading}</h1>
{body}
<p class="contact">Questions, or need a link? <a href="mailto:{CONTACT}">{CONTACT}</a></p>
"""


INVITE_ONLY = splash(
    "Invite only",
    "This demo is invite-only",
    """<p>You need a signed link from Graphide to open this box. Open that URL — not this page — so your browser can load the login cookie.</p>
<p>If you already had a link and it stopped working, it expired, this box is bound to someone else, or cookies were blocked.</p>""",
)

BUSY = splash(
    "Box reserved",
    "This box is reserved",
    "<p>This demo already has a guest link. Ask us for a new one if that reservation should be replaced.</p>",
)

ADMIN_PAGE = """<!doctype html>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Demo boxes</title>
<style>
  :root { color-scheme: dark; --bg: #0f0f10; --card: #18181a; --line: #2c2c30; --text: #ececec; --muted: #9a9aa3; --ok: #6dd38b; --warn: #e6b84f; --bad: #ff8a8a; --accent: #e8e8e8; }
  * { box-sizing: border-box; }
  body { font: 15px/1.45 system-ui, sans-serif; margin: 0; color: var(--text); background: var(--bg); }
  main { max-width: 52rem; margin: 0 auto; padding: 2.4rem 1.4rem 4rem; }
  header { display: flex; justify-content: space-between; align-items: baseline; gap: 1rem; margin-bottom: 1.6rem; }
  h1 { font-size: 1.35rem; font-weight: 600; margin: 0; }
  h2 { font-size: .78rem; font-weight: 650; letter-spacing: .08em; text-transform: uppercase; color: var(--muted); margin: 2rem 0 .7rem; }
  .hint { color: var(--muted); margin: 0; font-size: .92rem; }
  .cards { display: grid; grid-template-columns: repeat(3, 1fr); gap: .7rem; }
  .card { background: var(--card); border: 1px solid var(--line); border-radius: 10px; padding: .95rem 1rem; }
  .card .top { display: flex; justify-content: space-between; align-items: center; gap: .5rem; }
  .card .name { font-weight: 600; }
  .pill { font-size: .68rem; font-weight: 700; letter-spacing: .06em; text-transform: uppercase; }
  .ok { color: var(--ok); } .warn { color: var(--warn); } .bad { color: var(--bad); } .muted { color: var(--muted); }
  .guest { margin: .45rem 0 0; color: var(--muted); font-size: .9rem; min-height: 1.2em; }
  form.mint { background: var(--card); border: 1px solid var(--line); border-radius: 10px; padding: 1rem 1.05rem 1.1rem; display: grid; grid-template-columns: 1fr 1fr; gap: .75rem 1rem; }
  label { display: block; font-size: .8rem; color: var(--muted); margin-bottom: .3rem; }
  input, select, button { font: inherit; }
  input, select { width: 100%; padding: .5rem .6rem; border: 1px solid var(--line); background: #121214; color: inherit; border-radius: 7px; }
  .wide { grid-column: 1 / -1; }
  button.primary { grid-column: 1 / -1; margin-top: .2rem; padding: .6rem 1rem; border: 0; border-radius: 8px; background: var(--accent); color: #111; font-weight: 650; cursor: pointer; }
  button.primary:disabled { opacity: .5; cursor: default; }
  button.ghost { padding: .28rem .55rem; border: 1px solid var(--line); background: transparent; color: var(--text); border-radius: 6px; cursor: pointer; font-size: .82rem; }
  button.ghost:hover { background: #222; }
  button.danger { color: var(--bad); border-color: #5a3030; }
  .flash { display: none; margin-top: .9rem; padding: .85rem 1rem; background: var(--card); border: 1px solid var(--line); border-radius: 10px; word-break: break-all; }
  .flash a { color: #8cb4ff; }
  .err { color: var(--bad); }
  .links { display: flex; flex-direction: column; gap: .55rem; }
  .row { background: var(--card); border: 1px solid var(--line); border-radius: 10px; padding: .8rem 1rem; display: grid; grid-template-columns: 1fr auto; gap: .5rem 1rem; align-items: center; }
  .row .meta { color: var(--muted); font-size: .85rem; margin-top: .15rem; }
  .row .actions { display: flex; gap: .4rem; flex-shrink: 0; }
  .empty { color: var(--muted); }
  @media (max-width: 700px) {
    .cards, form.mint, .row { grid-template-columns: 1fr; }
    header { flex-direction: column; }
  }
</style>
<main>
  <header>
    <h1>Demo boxes</h1>
    <p class="hint">A minted link logs a guest into one box. They never see Authelia.</p>
  </header>
  <h2>Now</h2>
  <div class="cards" id="boxes">Loading…</div>
  <h2>Mint</h2>
  <form class="mint" id="f">
    <div>
      <label for="box">Box</label>
      <select id="box" name="box" required></select>
    </div>
    <div>
      <label for="ttl">Expires</label>
      <select id="ttl" name="ttl">
        <option value="12h">12 hours</option>
        <option value="1d">1 day</option>
        <option value="3d">3 days</option>
        <option value="7d" selected>1 week</option>
        <option value="14d">2 weeks</option>
      </select>
    </div>
    <div class="wide">
      <label for="label">Label</label>
      <input id="label" name="label" placeholder="press, friend, partner…" autocomplete="off">
    </div>
    <button class="primary" type="submit">Mint link</button>
  </form>
  <div class="flash" id="out"></div>
</main>
<script>
function esc(s) {
  return String(s)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;");
}
function when(ts) {
  if (!ts) return "";
  return new Date(ts * 1000).toLocaleString(undefined, { month: "short", day: "numeric", hour: "numeric", minute: "2-digit" });
}
async function load() {
  const res = await fetch("/api/demo/status", { credentials: "same-origin" });
  if (!res.ok) throw new Error("status " + res.status);
  const data = await res.json();
  const sel = document.getElementById("box");
  const prev = sel.value;
  sel.innerHTML = "";
  const free = data.boxes.filter(b => !b.reserved);
  free.forEach(b => {
    const o = document.createElement("option");
    o.value = b.name;
    o.textContent = b.name;
    sel.appendChild(o);
  });
  if (prev && free.some(b => b.name === prev)) sel.value = prev;
  document.getElementById("f").querySelector("button").disabled = free.length === 0;
  document.getElementById("boxes").innerHTML = data.boxes.map(b => {
    if (!b.reserved) {
      return '<div class="card"><div class="top"><span class="name">' + esc(b.name) + '</span><span class="pill ok">free</span></div><p class="guest">No link issued</p></div>';
    }
    return '<div class="card"><div class="top"><span class="name">' + esc(b.name) + '</span><span class="pill warn">reserved</span></div>' +
      '<p class="guest">' + esc(b.label || "untitled") + " · until " + when(b.exp) + "</p>" +
      '<div class="actions" style="margin-top:.7rem;display:flex;gap:.4rem">' +
      '<button class="ghost" data-copy="' + esc(b.url || "") + '">Copy</button>' +
      '<button class="ghost danger" data-revoke="' + esc(b.sid) + '">Revoke</button></div></div>';
  }).join("") || '<p class="empty">No boxes configured.</p>';
}
document.getElementById("f").addEventListener("submit", async (ev) => {
  ev.preventDefault();
  const out = document.getElementById("out");
  const btn = ev.target.querySelector("button");
  btn.disabled = true;
  out.style.display = "block";
  out.textContent = "Minting…";
  try {
    const res = await fetch("/api/demo/mint", {
      method: "POST",
      credentials: "same-origin",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        box: document.getElementById("box").value,
        ttl: document.getElementById("ttl").value,
        label: document.getElementById("label").value,
      }),
    });
    const text = await res.text();
    if (!res.ok) throw new Error(text || ("HTTP " + res.status));
    const data = JSON.parse(text);
    out.replaceChildren();
    const a = document.createElement("a");
    a.href = data.url;
    a.textContent = data.url;
    out.appendChild(a);
    try { await navigator.clipboard.writeText(data.url); } catch (_) {}
  } catch (err) {
    out.replaceChildren();
    const span = document.createElement("span");
    span.className = "err";
    span.textContent = err.message;
    out.appendChild(span);
  } finally {
    btn.disabled = false;
    load().catch(() => {});
  }
});
document.getElementById("boxes").addEventListener("click", async (ev) => {
  const copy = ev.target.closest("[data-copy]");
  if (copy) {
    try { await navigator.clipboard.writeText(copy.getAttribute("data-copy")); copy.textContent = "Copied"; } catch (_) {}
    return;
  }
  const rev = ev.target.closest("[data-revoke]");
  if (!rev) return;
  if (!confirm("Revoke this link? The box becomes free to mint again.")) return;
  const res = await fetch("/api/demo/revoke", {
    method: "POST",
    credentials: "same-origin",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ sid: rev.getAttribute("data-revoke") }),
  });
  if (!res.ok) alert(await res.text());
  load().catch(() => {});
});
load().catch(err => {
  document.getElementById("boxes").innerHTML = '<p class="err">' + esc(err.message) + "</p>";
});
</script>
"""


def b64url(raw: bytes) -> str:
    return base64.urlsafe_b64encode(raw).rstrip(b"=").decode("ascii")


def b64url_decode(text: str) -> bytes:
    pad = "=" * (-len(text) % 4)
    return base64.urlsafe_b64decode(text + pad)


MAX_TTL = 14 * 86400


def parse_duration(text: str) -> int:
    if text.isdigit():
        seconds = int(text)
    else:
        units = {"s": 1, "m": 60, "h": 3600, "d": 86400}
        unit = text[-1]
        if unit not in units:
            raise ValueError("ttl must look like 4h, 7d, 14d")
        seconds = int(text[:-1]) * units[unit]
    if seconds <= 0:
        raise ValueError("ttl must be positive")
    return min(seconds, MAX_TTL)


def load_key(hex_key: str) -> bytes:
    raw = bytes.fromhex(hex_key.strip())
    if len(raw) < 32:
        raise SystemExit("DEMO_GATE_KEY must be at least 32 bytes hex")
    return raw


def read_key_file(path: str) -> bytes:
    with open(path, encoding="utf-8") as handle:
        for line in handle:
            line = line.strip()
            if line.startswith("DEMO_GATE_KEY="):
                return load_key(line.split("=", 1)[1])
    raise SystemExit(f"no DEMO_GATE_KEY= in {path}")


def sign(payload: dict, key: bytes) -> str:
    body = json.dumps(payload, separators=(",", ":"), sort_keys=True).encode()
    mac = hmac.new(key, body, hashlib.sha256).digest()
    return f"{b64url(body)}.{b64url(mac)}"


def verify(token: str, key: bytes) -> dict:
    try:
        body_b64, mac_b64 = token.split(".", 1)
        body = b64url_decode(body_b64)
        expected = hmac.new(key, body, hashlib.sha256).digest()
        if not hmac.compare_digest(expected, b64url_decode(mac_b64)):
            raise ValueError("bad mac")
        payload = json.loads(body.decode("utf-8"))
    except (ValueError, json.JSONDecodeError, UnicodeDecodeError) as exc:
        raise ValueError("malformed token") from exc
    if int(payload["exp"]) < time.time():
        raise ValueError("expired")
    return payload


def mint_payload(box: str, ttl: int, label: str) -> dict:
    return {
        "box": box,
        "sid": secrets.token_urlsafe(16),
        "exp": int(time.time()) + ttl,
        "label": label[:80],
    }


def host_box(host_header: str, domain: str) -> str:
    host = (host_header or "").split(":", 1)[0].lower()
    suffix = "." + domain.lower()
    if not host.endswith(suffix):
        raise ValueError("host")
    return host[: -len(suffix)]


def parse_cookie(header: str) -> str | None:
    if not header:
        return None
    for part in header.split(";"):
        name, _, value = part.strip().partition("=")
        if name == COOKIE and value:
            return value
    return None


def parse_boxes(spec: str) -> list:
    names = []
    for item in spec.split(","):
        item = item.strip()
        if not item:
            continue
        names.append(item.split(":", 1)[0])
    return names


def load_state(path: str) -> dict:
    try:
        with open(path, encoding="utf-8") as handle:
            raw = json.load(handle)
    except (OSError, json.JSONDecodeError):
        raw = {}
    if not isinstance(raw, dict):
        raw = {}
    if "reservations" in raw:
        return {"reservations": raw.get("reservations") or {}}
    reservations = {}
    now = time.time()
    for link in raw.get("links") or []:
        if link.get("revoked"):
            continue
        if int(link.get("exp", 0)) < now:
            continue
        box = link.get("box")
        if box:
            reservations[box] = {
                "sid": link.get("sid", ""),
                "label": link.get("label", ""),
                "exp": link.get("exp", 0),
                "minted_at": link.get("minted_at", 0),
                "url": link.get("url", ""),
            }
    return {"reservations": reservations}


def save_state(path: str, state: dict) -> None:
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as handle:
        json.dump(state, handle, indent=2, sort_keys=True)
        handle.write("\n")
    os.replace(tmp, path)


def active_reservation(state: dict, box: str, now: float) -> dict | None:
    res = (state.get("reservations") or {}).get(box)
    if not res:
        return None
    if int(res.get("exp", 0)) < now:
        state["reservations"].pop(box, None)
        return None
    return res


STAFF_GROUPS = {
    g.strip()
    for g in os.environ.get("DEMO_STAFF_GROUPS", "admins,demo").split(",")
    if g.strip()
}


class Gate:
    def __init__(self, key, boxes, domain, state_path):
        self.key = key
        self.boxes = list(boxes)
        self.domain = domain
        self.state_path = state_path

    def claim_url(self, token: str, box: str) -> str:
        return f"https://{box}.{self.domain}/__claim?t={token}"

    def mint(self, box: str, ttl: int, label: str) -> tuple:
        if box not in self.boxes:
            raise ValueError(f"unknown box {box}")
        payload = mint_payload(box, ttl, label)
        token = sign(payload, self.key)
        url = self.claim_url(token, box)
        return url, payload


def make_handler(gate: Gate):
    class Handler(BaseHTTPRequestHandler):
        protocol_version = "HTTP/1.1"

        def log_message(self, fmt, *args):
            sys.stderr.write("%s - %s\n" % (self.address_string(), fmt % args))

        def _send(self, status, body, content_type="text/html; charset=utf-8", headers=None):
            data = body.encode("utf-8") if isinstance(body, str) else body
            self.send_response(status)
            self.send_header("Content-Type", content_type)
            self.send_header("Content-Length", str(len(data)))
            self.send_header("X-Content-Type-Options", "nosniff")
            self.send_header("Referrer-Policy", "no-referrer")
            self.send_header("Cache-Control", "no-store")
            if headers:
                for key, value in headers:
                    self.send_header(key, value)
            self.end_headers()
            self.wfile.write(data)

        def _host_box(self):
            forwarded = self.headers.get("X-Forwarded-Host", "")
            host = forwarded.split(",")[0].strip() or self.headers.get("Host", "")
            return host_box(host, gate.domain)

        def _is_staff(self):
            groups = self.headers.get("Remote-Groups", "")
            members = {g.strip() for g in groups.replace(",", " ").split() if g.strip()}
            return bool(members & STAFF_GROUPS)

        def do_GET(self):
            parsed = urlparse(self.path)
            if parsed.path == "/healthz":
                self._send(200, "ok\n", "text/plain; charset=utf-8")
                return
            if parsed.path == "/__claim":
                self._claim(parsed)
                return
            if parsed.path == "/api/demo/authz":
                self._authz()
                return
            if parsed.path in ("/demo", "/demo/"):
                if not self._is_staff():
                    self._send(403, INVITE_ONLY)
                    return
                self._send(200, ADMIN_PAGE)
                return
            if parsed.path == "/api/demo/status":
                self._status()
                return
            self._send(404, INVITE_ONLY)

        def do_POST(self):
            parsed = urlparse(self.path)
            if parsed.path == "/api/demo/mint":
                self._mint()
                return
            if parsed.path == "/api/demo/revoke":
                self._revoke()
                return
            self._send(404, "not found\n", "text/plain; charset=utf-8")

        def _mint(self):
            if not self._is_staff():
                self._send(403, "staff only\n", "text/plain; charset=utf-8")
                return
            length = int(self.headers.get("Content-Length", "0") or "0")
            raw = self.rfile.read(length) if length else b"{}"
            try:
                body = json.loads(raw.decode("utf-8") or "{}")
                box = body["box"]
                ttl = parse_duration(str(body.get("ttl", "7d")))
                label = str(body.get("label", ""))
            except (KeyError, ValueError, UnicodeDecodeError, json.JSONDecodeError) as exc:
                self._send(400, f"{exc}\n", "text/plain; charset=utf-8")
                return
            now = time.time()
            with STATE_LOCK:
                state = load_state(gate.state_path)
                if active_reservation(state, box, now):
                    self._send(409, "box already reserved\n", "text/plain; charset=utf-8")
                    return
                try:
                    url, payload = gate.mint(box, ttl, label)
                except ValueError as exc:
                    self._send(400, f"{exc}\n", "text/plain; charset=utf-8")
                    return
                state["reservations"][box] = {
                    "sid": payload["sid"],
                    "label": payload.get("label", ""),
                    "exp": payload["exp"],
                    "minted_at": int(now),
                    "url": url,
                }
                save_state(gate.state_path, state)
            self._send(200, json.dumps({"url": url, "sid": payload["sid"]}), "application/json")

        def _revoke(self):
            if not self._is_staff():
                self._send(403, "staff only\n", "text/plain; charset=utf-8")
                return
            length = int(self.headers.get("Content-Length", "0") or "0")
            raw = self.rfile.read(length) if length else b"{}"
            try:
                body = json.loads(raw.decode("utf-8") or "{}")
                sid = body["sid"]
            except (KeyError, ValueError, UnicodeDecodeError, json.JSONDecodeError) as exc:
                self._send(400, f"{exc}\n", "text/plain; charset=utf-8")
                return
            with STATE_LOCK:
                state = load_state(gate.state_path)
                found = None
                for box, res in list(state["reservations"].items()):
                    if res.get("sid") == sid:
                        found = box
                        break
                if not found:
                    self._send(404, "unknown link\n", "text/plain; charset=utf-8")
                    return
                state["reservations"].pop(found, None)
                save_state(gate.state_path, state)
            self._send(200, json.dumps({"ok": True}), "application/json")

        def _status(self):
            if not self._is_staff():
                self._send(403, "staff only\n", "text/plain; charset=utf-8")
                return
            now = time.time()
            boxes = []
            with STATE_LOCK:
                state = load_state(gate.state_path)
                dirty = False
                for name in gate.boxes:
                    res = (state.get("reservations") or {}).get(name)
                    if res and int(res.get("exp", 0)) < now:
                        state["reservations"].pop(name, None)
                        res = None
                        dirty = True
                    if res:
                        boxes.append({
                            "name": name,
                            "reserved": True,
                            "label": res.get("label", ""),
                            "sid": res.get("sid", ""),
                            "exp": res.get("exp", 0),
                            "url": res.get("url", ""),
                        })
                    else:
                        boxes.append({"name": name, "reserved": False})
                if dirty:
                    save_state(gate.state_path, state)
            self._send(200, json.dumps({"boxes": boxes}), "application/json")

        def _claim(self, parsed):
            token = (parse_qs(parsed.query).get("t") or [None])[0]
            if not token:
                self._send(401, INVITE_ONLY)
                return
            try:
                payload = verify(token, gate.key)
                box = self._host_box()
            except ValueError:
                self._send(401, INVITE_ONLY)
                return
            if payload.get("box") != box or box not in gate.boxes:
                self._send(401, INVITE_ONLY)
                return
            now = time.time()
            with STATE_LOCK:
                state = load_state(gate.state_path)
                res = active_reservation(state, box, now)
                if not res or res.get("sid") != payload["sid"]:
                    self._send(401, INVITE_ONLY if not res else BUSY)
                    return
                save_state(gate.state_path, state)
            max_age = max(0, int(payload["exp"] - now))
            cookie = (
                f"{COOKIE}={token}; HttpOnly; Secure; SameSite=Lax; Path=/; Max-Age={max_age}"
            )
            self._send(302, "", "text/plain; charset=utf-8", [("Set-Cookie", cookie), ("Location", "/")])

        def _authz(self):
            token = parse_cookie(self.headers.get("Cookie", ""))
            if not token:
                self._send(401, INVITE_ONLY)
                return
            try:
                payload = verify(token, gate.key)
                box = self._host_box()
            except ValueError:
                self._send(401, INVITE_ONLY)
                return
            if payload.get("box") != box or box not in gate.boxes:
                self._send(401, INVITE_ONLY)
                return
            now = time.time()
            with STATE_LOCK:
                state = load_state(gate.state_path)
                res = active_reservation(state, box, now)
                if not res or res.get("sid") != payload["sid"]:
                    self._send(401, INVITE_ONLY if not res else BUSY)
                    return
                save_state(gate.state_path, state)
            self._send(200, "ok\n", "text/plain; charset=utf-8")

    return Handler


def cmd_selftest() -> int:
    key = os.urandom(32)
    token = sign(mint_payload("demobox1", 60, "t"), key)
    payload = verify(token, key)
    assert payload["box"] == "demobox1"
    assert parse_duration("7d") == 7 * 86400
    assert parse_duration("14d") == MAX_TTL
    assert parse_duration("30d") == MAX_TTL
    body, mac = token.split(".", 1)
    forged = f"{body}.{('A' if mac[0] != 'A' else 'B')}{mac[1:]}"
    try:
        verify(forged, key)
    except ValueError:
        print("selftest ok")
        return 0
    raise SystemExit("selftest: forged token accepted")


def cmd_mint(args) -> int:
    key = read_key_file(args.key_file) if args.key_file else load_key(args.key)
    boxes = parse_boxes(args.boxes)
    gate = Gate(key, boxes, args.domain, "/dev/null")
    url, _payload = gate.mint(args.box, parse_duration(args.ttl), args.label)
    print(url)
    return 0


def cmd_serve(_args) -> int:
    key = load_key(os.environ["DEMO_GATE_KEY"])
    boxes = parse_boxes(os.environ.get("DEMO_BOXES", "demobox1,demobox2,demobox3"))
    domain = os.environ.get("DEMO_DOMAIN", "graphide.net")
    state_path = os.environ.get("DEMO_GATE_STATE", "/var/lib/graphide-gate/state.json")
    listen = os.environ.get("DEMO_GATE_LISTEN", "127.0.0.1:8011")
    host, port_s = listen.rsplit(":", 1)
    os.makedirs(os.path.dirname(state_path), exist_ok=True)
    gate = Gate(key, boxes, domain, state_path)
    server = ThreadingHTTPServer((host, int(port_s)), make_handler(gate))
    sys.stderr.write(f"graphide-gate listening on {listen}\n")
    server.serve_forever()
    return 0


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(prog="graphide-gate")
    sub = parser.add_subparsers(dest="cmd", required=True)

    sub.add_parser("serve", help="run the Caddy forward_auth endpoint")
    sub.add_parser("selftest", help="HMAC round-trip")

    mint_p = sub.add_parser("mint", help="print a magic link")
    mint_p.add_argument("--box", required=True)
    mint_p.add_argument("--ttl", default="7d")
    mint_p.add_argument("--label", default="")
    mint_p.add_argument("--domain", default=os.environ.get("DEMO_DOMAIN", "graphide.net"))
    mint_p.add_argument("--boxes", default=os.environ.get("DEMO_BOXES", "demobox1,demobox2,demobox3"))
    mint_p.add_argument("--key-file", default=os.environ.get("DEMO_GATE_KEY_FILE"))
    mint_p.add_argument("--key", default=os.environ.get("DEMO_GATE_KEY"))

    args = parser.parse_args(argv)
    if args.cmd == "selftest":
        return cmd_selftest()
    if args.cmd == "mint":
        if not args.key_file and not args.key:
            raise SystemExit("pass --key-file or DEMO_GATE_KEY")
        return cmd_mint(args)
    return cmd_serve(args)


if __name__ == "__main__":
    sys.exit(main())
