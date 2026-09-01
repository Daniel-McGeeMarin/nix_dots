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
<html lang="en">
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="theme-color" content="#0a1218">
<title>Demo boxes · Graphide</title>
<link rel="icon" type="image/svg+xml" href="/favicon.svg">
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600&family=JetBrains+Mono:wght@400;500&display=swap" rel="stylesheet">
<style>
  :root {
    color-scheme: dark;
    --page: #0a1218;
    --raised: #0f1a22;
    --overlay: #0d1720;
    --text: #bcc6cd;
    --muted: #75838b;
    --dim: #556067;
    --hairline: #ffffff14;
    --verdigris: #4fa396;
    --verdigris-soft: #79b0a8;
    --verdigris-on: #04120f;
    --error: #f85149;
    --warn: #e3b341;
    --sans: Inter, ui-sans-serif, system-ui, sans-serif;
    --mono: "JetBrains Mono", ui-monospace, SFMono-Regular, monospace;
  }
  * { box-sizing: border-box; }
  html, body { margin: 0; background: var(--page); color: var(--text); }
  body { font: 15px/1.5 var(--sans); min-height: 100vh; }
  a { color: var(--verdigris-soft); text-decoration: none; }
  a:hover { color: #6dbcb0; }
  .bar {
    display: flex; align-items: center; justify-content: space-between;
    max-width: 64rem; margin: 0 auto; padding: 1.15rem 1.5rem;
    border-bottom: 1px solid #ffffff0a;
  }
  .brand { display: flex; align-items: center; gap: .65rem; color: var(--text); font-weight: 500; letter-spacing: -.025em; }
  .brand svg { width: 1.65rem; height: 1.65rem; }
  .badge {
    font: 500 11px/1 var(--mono); letter-spacing: .04em; color: var(--muted);
    border: 1px solid var(--hairline); border-radius: 999px; padding: .35rem .75rem;
  }
  main { max-width: 64rem; margin: 0 auto; padding: 2.4rem 1.5rem 4.5rem; }
  .intro { margin-bottom: 1.6rem; }
  h1 { margin: 0 0 .4rem; font-size: 1.7rem; font-weight: 500; letter-spacing: -.03em; color: #e4eaee; }
  .lede { margin: 0; color: var(--muted); max-width: 36rem; }
  .tally { font: 400 12px/1 var(--mono); color: var(--dim); letter-spacing: .04em; text-transform: uppercase; margin: 0 0 .85rem; }
  .tiles { display: grid; grid-template-columns: repeat(3, 1fr); gap: .9rem; }
  .tile {
    background: var(--raised); border: 1px solid var(--hairline); border-radius: 1rem;
    padding: 1.15rem 1.15rem 1.2rem; display: flex; flex-direction: column; min-height: 17.5rem;
    transition: border-color .2s, background-color .2s, box-shadow .2s;
  }
  .tile:hover { background: var(--overlay); border-color: color-mix(in oklab, var(--verdigris) 28%, transparent); }
  .tile.held { box-shadow: inset 3px 0 0 var(--verdigris); }
  .top { display: flex; justify-content: space-between; align-items: baseline; gap: .6rem; }
  .name { font: 500 13px/1.2 var(--mono); letter-spacing: .01em; color: #e4eaee; }
  .pill { font: 500 10px/1 var(--mono); letter-spacing: .08em; text-transform: uppercase; }
  .free .pill { color: var(--verdigris-soft); }
  .held .pill { color: var(--warn); }
  .who { margin: 1.15rem 0 .35rem; font-size: 1.15rem; font-weight: 500; letter-spacing: -.02em; color: #e4eaee; }
  .meta { margin: 0; color: var(--muted); font-size: .9rem; }
  .remain { margin: .2rem 0 0; color: var(--verdigris-soft); font: 400 12px/1.4 var(--mono); }
  form.mint { margin-top: auto; display: grid; gap: .7rem; padding-top: 1.1rem; }
  label { display: block; font-size: .72rem; font-weight: 500; letter-spacing: .06em; text-transform: uppercase; color: var(--dim); margin-bottom: .3rem; }
  input, select, button { font: inherit; }
  input, select {
    width: 100%; padding: .55rem .7rem; border: 1px solid var(--hairline);
    background: var(--page); color: inherit; border-radius: .5rem;
  }
  input:focus, select:focus { outline: none; border-color: color-mix(in oklab, var(--verdigris) 55%, transparent); }
  input::placeholder { color: var(--dim); }
  .actions { display: flex; flex-wrap: wrap; gap: .4rem; margin-top: auto; padding-top: 1.2rem; }
  button { cursor: pointer; }
  button.primary {
    width: 100%; padding: .62rem .9rem; border: 0; border-radius: .5rem;
    background: var(--verdigris); color: var(--verdigris-on); font-weight: 600;
  }
  button.primary:hover { background: var(--verdigris-soft); }
  button.primary:disabled { opacity: .45; cursor: default; }
  button.ghost, a.ghost {
    display: inline-flex; align-items: center; padding: .38rem .7rem;
    border: 1px solid var(--hairline); background: transparent; color: var(--text);
    border-radius: .45rem; font-size: .82rem;
  }
  button.ghost:hover, a.ghost:hover { background: var(--overlay); color: var(--text); }
  button.danger { color: var(--error); border-color: color-mix(in oklab, var(--error) 35%, transparent); }
  .flash {
    margin-top: 1.1rem; padding: 1rem 1.1rem; background: var(--raised);
    border: 1px solid color-mix(in oklab, var(--verdigris) 35%, transparent);
    border-radius: 1rem; display: none;
  }
  .flash.show { display: block; }
  .flash .kicker { font: 500 11px/1 var(--mono); letter-spacing: .06em; text-transform: uppercase; color: var(--verdigris-soft); margin: 0 0 .45rem; }
  .flash a { word-break: break-all; }
  .err { color: var(--error); }
  .empty { color: var(--muted); }
  @media (max-width: 820px) { .tiles { grid-template-columns: 1fr; } .tile { min-height: 0; } }
</style>
<header class="bar">
  <a class="brand" href="https://graphide.net/">
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" aria-hidden="true">
      <defs><linearGradient id="m" x1="0" y1="0" x2="1" y2="1"><stop offset="0%" stop-color="#79b0a8"/><stop offset="100%" stop-color="#3f8a7e"/></linearGradient></defs>
      <g stroke="url(#m)" stroke-width="1.4" stroke-linecap="round">
        <line x1="9.1" y1="6.5" x2="14.9" y2="6.5"/><line x1="7.58" y1="8.86" x2="10.92" y2="16.14"/>
        <line x1="16.42" y1="8.86" x2="13.08" y2="16.14"/>
        <circle cx="6.5" cy="6.5" r="2.6" fill="url(#m)" stroke="none"/>
        <circle cx="17.5" cy="6.5" r="2.6" fill="url(#m)" stroke="none"/>
        <circle cx="12" cy="18.5" r="2.6" fill="url(#m)" stroke="none"/>
      </g>
    </svg>
    graphide
  </a>
  <span class="badge">Staff</span>
</header>
<main>
  <div class="intro">
    <h1>Demo boxes</h1>
    <p class="lede">A minted link holds one box until it expires or you revoke it. The guest never sees Authelia.</p>
  </div>
  <p class="tally" id="tally"></p>
  <div class="tiles" id="boxes">Loading…</div>
  <div class="flash" id="out"></div>
</main>
<script>
const TTL = '<option value="12h">12 hours</option><option value="1d">1 day</option><option value="3d">3 days</option><option value="7d" selected>1 week</option><option value="14d">2 weeks</option>';
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
function left(exp) {
  const s = Math.max(0, Math.floor(exp - Date.now() / 1000));
  const d = Math.floor(s / 86400);
  const h = Math.floor((s % 86400) / 3600);
  const m = Math.floor((s % 3600) / 60);
  if (d >= 2) return d + " days left";
  if (d === 1) return "1 day " + h + "h left";
  if (h >= 1) return h + "h " + m + "m left";
  return m + "m left";
}
function card(b) {
  if (!b.reserved) {
    return '<article class="tile free"><div class="top"><span class="name">' + esc(b.name) + '</span><span class="pill">Free</span></div>' +
      '<p class="who">Available</p><p class="meta">No guest link yet.</p>' +
      '<form class="mint" data-box="' + esc(b.name) + '">' +
      '<div><label for="l-' + esc(b.name) + '">Who</label><input id="l-' + esc(b.name) + '" name="label" placeholder="press, partner, friend…" autocomplete="off"></div>' +
      '<div><label for="t-' + esc(b.name) + '">Hold for</label><select id="t-' + esc(b.name) + '" name="ttl">' + TTL + '</select></div>' +
      '<button class="primary" type="submit">Mint link</button></form></article>';
  }
  return '<article class="tile held"><div class="top"><span class="name">' + esc(b.name) + '</span><span class="pill">Reserved</span></div>' +
    '<p class="who">' + esc(b.label || "untitled") + '</p>' +
    '<p class="meta">Until ' + when(b.exp) + '</p>' +
    '<p class="remain">' + left(b.exp) + '</p>' +
    '<div class="actions">' +
    '<button class="ghost" data-copy="' + esc(b.url || "") + '">Copy link</button>' +
    '<a class="ghost" href="' + esc(b.url || "#") + '" target="_blank" rel="noopener">Open</a>' +
    '<button class="ghost danger" data-revoke="' + esc(b.sid) + '">Revoke</button></div></article>';
}
function flash(html, isErr) {
  const out = document.getElementById("out");
  out.classList.add("show");
  out.className = "flash show" + (isErr ? " err" : "");
  if (typeof html === "string") out.innerHTML = html;
  else { out.replaceChildren(); out.appendChild(html); }
}
async function load() {
  const res = await fetch("/api/demo/status", { credentials: "same-origin" });
  if (!res.ok) throw new Error("Could not load boxes (" + res.status + ")");
  const data = await res.json();
  const free = data.boxes.filter(b => !b.reserved).length;
  document.getElementById("tally").textContent =
    free + " of " + data.boxes.length + " free";
  document.getElementById("boxes").innerHTML =
    data.boxes.map(card).join("") || '<p class="empty">No boxes configured.</p>';
}
document.getElementById("boxes").addEventListener("submit", async (ev) => {
  const form = ev.target.closest("form.mint");
  if (!form) return;
  ev.preventDefault();
  const btn = form.querySelector("button");
  btn.disabled = true;
  flash('<p class="kicker">Minting</p><p>Holding ' + esc(form.dataset.box) + "…</p>');
  try {
    const res = await fetch("/api/demo/mint", {
      method: "POST",
      credentials: "same-origin",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        box: form.dataset.box,
        ttl: form.ttl.value,
        label: form.label.value,
      }),
    });
    const text = await res.text();
    if (!res.ok) throw new Error(text.trim() || ("HTTP " + res.status));
    const data = JSON.parse(text);
    const wrap = document.createElement("div");
    const k = document.createElement("p");
    k.className = "kicker";
    k.textContent = "Link copied · " + form.dataset.box;
    const a = document.createElement("a");
    a.href = data.url;
    a.textContent = data.url;
    wrap.append(k, a);
    flash(wrap);
    try { await navigator.clipboard.writeText(data.url); } catch (_) {}
  } catch (err) {
    flash('<p class="kicker">Could not mint</p><p class="err">' + esc(err.message) + "</p>", true);
  } finally {
    btn.disabled = false;
    load().catch(() => {});
  }
});
document.getElementById("boxes").addEventListener("click", async (ev) => {
  const copy = ev.target.closest("[data-copy]");
  if (copy) {
    try {
      await navigator.clipboard.writeText(copy.getAttribute("data-copy"));
      copy.textContent = "Copied";
      setTimeout(() => { copy.textContent = "Copy link"; }, 1400);
    } catch (_) {}
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
  if (!res.ok) flash('<p class="err">' + esc(await res.text()) + "</p>", true);
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
                            "minted_at": res.get("minted_at", 0),
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
