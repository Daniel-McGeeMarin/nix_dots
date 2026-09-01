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

INVITE_ONLY = """<!doctype html>
<meta charset="utf-8">
<title>Invite only</title>
<style>
  body { font: 16px/1.4 system-ui, sans-serif; max-width: 36em; margin: 20vh auto; padding: 0 1.5rem; color: #111; }
</style>
<h1>This demo is invite-only</h1>
<p>You need a signed link from Graphide to open this box.</p>
"""

BUSY = """<!doctype html>
<meta charset="utf-8">
<title>Box busy</title>
<style>
  body { font: 16px/1.4 system-ui, sans-serif; max-width: 36em; margin: 20vh auto; padding: 0 1.5rem; color: #111; }
</style>
<h1>This box is in use</h1>
<p>Someone else is on this demo right now. Ask for a new link when it is free.</p>
"""


def b64url(raw: bytes) -> str:
    return base64.urlsafe_b64encode(raw).rstrip(b"=").decode("ascii")


def b64url_decode(text: str) -> bytes:
    pad = "=" * (-len(text) % 4)
    return base64.urlsafe_b64decode(text + pad)


def parse_duration(text: str) -> int:
    if text.isdigit():
        return int(text)
    units = {"s": 1, "m": 60, "h": 3600, "d": 86400}
    unit = text[-1]
    if unit not in units:
        raise ValueError("ttl must look like 4h, 30m, 12h")
    return int(text[:-1]) * units[unit]


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


def parse_boxes(spec: str) -> dict[str, int]:
    out = {}
    for item in spec.split(","):
        item = item.strip()
        if not item:
            continue
        name, _, port = item.partition(":")
        out[name] = int(port)
    return out


def tcp_established(port: int) -> int:
    """Count ESTABLISHED sockets bound to 127.0.0.1:port (host namespace)."""
    needle = f"0100007F:{port:04X}"
    count = 0
    try:
        with open("/proc/net/tcp", encoding="utf-8") as handle:
            next(handle)
            for line in handle:
                fields = line.split()
                if len(fields) < 4:
                    continue
                if fields[1] == needle and fields[3] == "01":
                    count += 1
    except OSError:
        return 0
    return count


def load_state(path: str) -> dict:
    try:
        with open(path, encoding="utf-8") as handle:
            return json.load(handle)
    except (OSError, json.JSONDecodeError):
        return {}


def save_state(path: str, state: dict) -> None:
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as handle:
        json.dump(state, handle, indent=2, sort_keys=True)
        handle.write("\n")
    os.replace(tmp, path)


def is_busy(entry: dict | None, port: int, grace: int, now: float) -> bool:
    if tcp_established(port) > 0:
        return True
    if not entry:
        return False
    last = float(entry.get("last_tcp", 0))
    return last > 0 and (now - last) < grace


def refresh_tcp(entry: dict, port: int, now: float) -> None:
    if tcp_established(port) > 0:
        entry["last_tcp"] = now


class Gate:
    def __init__(self, key, boxes, domain, state_path, grace):
        self.key = key
        self.boxes = boxes
        self.domain = domain
        self.state_path = state_path
        self.grace = grace

    def claim_url(self, token: str, box: str) -> str:
        return f"https://{box}.{self.domain}/__claim?t={token}"

    def mint(self, box: str, ttl: int, label: str) -> str:
        if box not in self.boxes:
            raise ValueError(f"unknown box {box}")
        token = sign(mint_payload(box, ttl, label), self.key)
        return self.claim_url(token, box)


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
            self._send(404, INVITE_ONLY)

        def do_POST(self):
            parsed = urlparse(self.path)
            if parsed.path == "/api/demo/mint":
                self._mint()
                return
            self._send(404, "not found\n", "text/plain; charset=utf-8")

        def _mint(self):
            groups = self.headers.get("Remote-Groups", "")
            members = {g.strip() for g in groups.replace(",", " ").split() if g.strip()}
            if "admins" not in members:
                self._send(403, "admin only\n", "text/plain; charset=utf-8")
                return
            length = int(self.headers.get("Content-Length", "0") or "0")
            raw = self.rfile.read(length) if length else b"{}"
            try:
                body = json.loads(raw.decode("utf-8") or "{}")
                box = body["box"]
                ttl = parse_duration(str(body.get("ttl", "12h")))
                label = str(body.get("label", ""))
                url = gate.mint(box, ttl, label)
            except (KeyError, ValueError, UnicodeDecodeError, json.JSONDecodeError) as exc:
                self._send(400, f"{exc}\n", "text/plain; charset=utf-8")
                return
            payload = json.dumps({"url": url}).encode()
            self._send(200, payload, "application/json")

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
            port = gate.boxes[box]
            with STATE_LOCK:
                state = load_state(gate.state_path)
                occupant = state.get(box)
                if occupant:
                    refresh_tcp(occupant, port, now)
                if (
                    occupant
                    and occupant.get("sid") != payload["sid"]
                    and is_busy(occupant, port, gate.grace, now)
                ):
                    self._send(409, BUSY)
                    return
                last_tcp = occupant.get("last_tcp", 0) if occupant else 0
                if tcp_established(port) > 0:
                    last_tcp = now
                state[box] = {
                    "sid": payload["sid"],
                    "label": payload.get("label", ""),
                    "exp": payload["exp"],
                    "bound_at": now,
                    "last_tcp": last_tcp,
                }
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
            port = gate.boxes[box]
            with STATE_LOCK:
                state = load_state(gate.state_path)
                occupant = state.get(box)
                refresh_tcp(occupant, port, now) if occupant else None
                occupant = state.get(box)
                if not occupant or occupant.get("sid") != payload["sid"]:
                    if occupant and is_busy(occupant, port, gate.grace, now):
                        self._send(401, BUSY)
                    else:
                        self._send(401, INVITE_ONLY)
                    return
                refresh_tcp(occupant, port, now)
                save_state(gate.state_path, state)
            self._send(200, "ok\n", "text/plain; charset=utf-8")

    return Handler


def cmd_selftest() -> int:
    key = os.urandom(32)
    token = sign(mint_payload("demobox1", 60, "t"), key)
    payload = verify(token, key)
    assert payload["box"] == "demobox1"
    try:
        verify(token[:-1] + ("A" if token[-1] != "A" else "B"), key)
    except ValueError:
        print("selftest ok")
        return 0
    raise SystemExit("selftest: forged token accepted")


def cmd_mint(args) -> int:
    key = read_key_file(args.key_file) if args.key_file else load_key(args.key)
    boxes = parse_boxes(args.boxes) if ":" in args.boxes else {b: 0 for b in args.boxes.split(",") if b}
    gate = Gate(key, boxes, args.domain, "/dev/null", 0)
    url = gate.mint(args.box, parse_duration(args.ttl), args.label)
    print(url)
    return 0


def cmd_serve(_args) -> int:
    key = load_key(os.environ["DEMO_GATE_KEY"])
    boxes = parse_boxes(os.environ["DEMO_BOX_PORTS"])
    domain = os.environ.get("DEMO_DOMAIN", "graphide.net")
    state_path = os.environ.get("DEMO_GATE_STATE", "/var/lib/graphide-gate/state.json")
    grace = int(os.environ.get("DEMO_IDLE_GRACE", "300"))
    listen = os.environ.get("DEMO_GATE_LISTEN", "127.0.0.1:8011")
    host, port_s = listen.rsplit(":", 1)
    os.makedirs(os.path.dirname(state_path), exist_ok=True)
    gate = Gate(key, boxes, domain, state_path, grace)
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
    mint_p.add_argument("--ttl", default="12h")
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
