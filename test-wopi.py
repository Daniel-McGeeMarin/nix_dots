#!/usr/bin/env python3
"""
OnlyOffice WOPI flow diagnostic.

How to get the token:
  1. Open OCIS in your browser and click a .docx file to open it.
  2. Open DevTools → Network tab (filter: "hosting/wopi").
  3. Find the POST request to office.mcgeedan.com/hosting/wopi/...
  4. Click the request → Payload tab → copy the access_token value.
  5. Also copy the full Request URL (the WOPISrc=... one).
  6. Run: python3 test-wopi.py '<request-url>' '<access_token>'

The token expires in ~10 minutes, so grab it quickly.

Example:
  python3 test-wopi.py \\
    'https://office.mcgeedan.com/hosting/wopi/word/edit?WOPISrc=https%3A%2F%2Fcloud.mcgeedan.com%2Fwopi%2Ffiles%2FXXX&ui=en-US' \\
    'eyJ...' \\
    '1752401234000'
"""

import sys
import urllib.request
import urllib.parse
import re
import json


def parse_field(html, field_id):
    """Extract data-json attribute from a div with the given id."""
    pattern = rf'id="{field_id}"[^>]*data-json="([^"]*)"'
    m = re.search(pattern, html)
    if not m:
        return None
    val = m.group(1)
    val = val.replace("&quot;", '"').replace("&amp;", "&").replace("&#39;", "'")
    return val


def post_wopi_action(url, access_token, access_token_ttl=""):
    params = {"access_token": access_token}
    if access_token_ttl:
        params["access_token_ttl"] = access_token_ttl
    body = urllib.parse.urlencode(params).encode()
    req = urllib.request.Request(url, data=body, method="POST")
    req.add_header("Content-Type", "application/x-www-form-urlencoded")
    req.add_header("User-Agent", "Mozilla/5.0 (WOPI-test)")
    req.add_header("Accept", "text/html,application/xhtml+xml")
    with urllib.request.urlopen(req, timeout=30) as resp:
        return resp.status, resp.read().decode("utf-8", errors="replace")


def check_file_info(wopi_src, access_token):
    url = f"{wopi_src}?access_token={urllib.parse.quote(access_token)}"
    req = urllib.request.Request(url)
    req.add_header("Accept", "application/json")
    with urllib.request.urlopen(req, timeout=10) as resp:
        return resp.status, resp.read().decode()


def test_socketio(key):
    url = f"http://127.0.0.1:8090/doc/{key}/c/?EIO=4&transport=polling"
    req = urllib.request.Request(url)
    with urllib.request.urlopen(req, timeout=5) as resp:
        return resp.status, resp.read().decode()


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        sys.exit(1)

    url          = sys.argv[1]
    access_token = sys.argv[2]
    ttl          = sys.argv[3] if len(sys.argv) > 3 else ""

    parsed   = urllib.parse.urlparse(url)
    qs       = urllib.parse.parse_qs(parsed.query)
    wopi_src = qs.get("WOPISrc", [None])[0]

    print("=" * 60)
    print("STEP 1: POST to OnlyOffice WOPI action endpoint")
    print("=" * 60)
    print(f"URL:          {url[:100]}{'...' if len(url) > 100 else ''}")
    print(f"WOPISrc:      {wopi_src}")
    print(f"access_token: {access_token[:30]}...")
    print()

    try:
        status, html = post_wopi_action(url, access_token, ttl)
    except Exception as e:
        print(f"FAILED: {e}")
        sys.exit(1)

    print(f"HTTP {status} — got {len(html)} bytes of HTML")
    print()

    # --- Extract key fields ---
    key_data       = parse_field(html, "keyData")
    file_info_raw  = parse_field(html, "fileInfoJsonData")
    config_raw     = parse_field(html, "docsApiConfigJsonData")
    user_auth_raw  = parse_field(html, "userAuthJsonData")
    query_params_raw = parse_field(html, "queryParamsJsonData")

    js_status_m = re.search(r'var statusCode\s*=\s*"([^"]*)"', html)
    js_status   = js_status_m.group(1) if js_status_m else "(not found)"

    print("=" * 60)
    print("STEP 2: Check critical page fields")
    print("=" * 60)

    if js_status == "":
        print(f"[OK]  statusCode = '' (token accepted)")
    else:
        print(f"[BAD] statusCode = '{js_status}' — token rejected or error.")
        print(f"      Editor will call handleWopiError and never reach DocsAPI.DocEditor.")

    if key_data:
        print(f"[OK]  keyData = '{key_data[:80]}{'...' if len(key_data) > 80 else ''}'")
    else:
        print(f"[BAD] keyData = empty — docservice key not set. Socket.IO will never connect.")

    fi = None
    if file_info_raw and file_info_raw != "{}":
        try:
            fi = json.loads(file_info_raw)
            bn = fi.get("BaseFileName", "MISSING")
            ucw = fi.get("UserCanWrite", "MISSING")
            sup = fi.get("SupportsUpdate", "MISSING")
            ver = fi.get("Version", "MISSING")
            pmo = fi.get("PostMessageOrigin", "(not set)")
            print(f"[OK]  fileInfoJsonData:")
            print(f"        BaseFileName={bn}, UserCanWrite={ucw}, SupportsUpdate={sup}")
            print(f"        Version={ver}, PostMessageOrigin={pmo}")
        except Exception:
            print(f"[BAD] fileInfoJsonData invalid JSON: {file_info_raw[:80]}")
    else:
        print(f"[BAD] fileInfoJsonData = empty/{{}} — CheckFileInfo did not populate.")

    doc_key = None
    if config_raw and config_raw != "{}":
        try:
            cfg = json.loads(config_raw)
            doc_key  = cfg.get("document", {}).get("key")
            doc_url  = cfg.get("document", {}).get("url", "?")
            doc_type = cfg.get("documentType", "?")
            mode     = cfg.get("editorConfig", {}).get("mode", "?")
            cb_url   = cfg.get("editorConfig", {}).get("callbackUrl", "?")
            print(f"[OK]  docsApiConfigJsonData:")
            print(f"        documentType={doc_type}, mode={mode}")
            print(f"        document.key={doc_key}")
            print(f"        document.url={doc_url[:100]}")
            print(f"        callbackUrl={cb_url[:100]}")
        except Exception:
            print(f"[BAD] docsApiConfigJsonData invalid JSON")
    else:
        print(f"[BAD] docsApiConfigJsonData = empty/{{}} — editor config not built.")

    effective_key = key_data or doc_key
    print()

    # --- Direct CheckFileInfo test ---
    print("=" * 60)
    print("STEP 3: Direct CheckFileInfo call (bypasses OnlyOffice)")
    print("=" * 60)
    if wopi_src:
        print(f"WOPISrc: {wopi_src}")
        try:
            cfi_status, cfi_body = check_file_info(wopi_src, access_token)
            if cfi_status == 200:
                try:
                    info = json.loads(cfi_body)
                    print(f"[OK]  HTTP {cfi_status}: BaseFileName={info.get('BaseFileName')}, "
                          f"Size={info.get('Size')}, UserCanWrite={info.get('UserCanWrite')}")
                    if info.get("PostMessageOrigin"):
                        print(f"      PostMessageOrigin: {info['PostMessageOrigin']}")
                except Exception:
                    print(f"HTTP {cfi_status}: (non-JSON) {cfi_body[:120]}")
            else:
                print(f"[BAD] CheckFileInfo HTTP {cfi_status}: {cfi_body[:200]}")
        except Exception as e:
            print(f"[ERR] {e}")
    else:
        print("[SKIP] Could not extract WOPISrc from URL")
    print()

    # --- Socket.IO test ---
    if effective_key:
        print("=" * 60)
        print("STEP 4: Socket.IO polling test (docservice reachability)")
        print("=" * 60)
        print(f"Key: {effective_key}")
        try:
            sio_status, sio_body = test_socketio(effective_key)
            if '"sid"' in sio_body:
                print(f"[OK]  Socket.IO polling HTTP {sio_status}: got session — docservice is reachable")
                print(f"      {sio_body[:120]}")
            else:
                print(f"[BAD] Socket.IO polling HTTP {sio_status}: no session ID")
                print(f"      {sio_body[:120]}")
        except Exception as e:
            print(f"[ERR] Socket.IO polling failed: {e}")
    else:
        print("[SKIP] No docservice key found — cannot test Socket.IO")
    print()

    # --- Summary ---
    print("=" * 60)
    print("DIAGNOSIS")
    print("=" * 60)
    if js_status != "":
        print("Root cause: token rejected by OnlyOffice (statusCode non-empty).")
        print("  -> The access_token passed as arg2 was invalid or expired.")
        print("  -> Grab a fresh token from DevTools → POST request → Payload tab.")
    elif not (file_info_raw and file_info_raw != "{}"):
        print("Root cause: fileInfoJsonData is empty.")
        print("  -> OnlyOffice accepted the token but CheckFileInfo returned no data.")
        print("  -> Check: does the OnlyOffice container resolve cloud.mcgeedan.com?")
        print("  -> Run from inside the onlyoffice container:")
        print(f"     sudo podman exec onlyoffice curl -s '{wopi_src}?access_token=<token>'")
    elif not effective_key:
        print("Root cause: docservice key is empty despite valid token + fileInfo.")
        print("  -> OnlyOffice built the page but skipped generating the doc key.")
        print("  -> Check docservice logs: sudo podman exec onlyoffice supervisorctl tail -1000 docservice")
    else:
        print("Server-side fields look correct (token OK, fileInfo populated, key set).")
        print("The editor config (docsApiConfigJsonData) should drive Socket.IO setup.")
        print()
        print("If no Socket.IO connections appear in browser Network tab:")
        print("  -> Check browser Console for JS errors after clicking the file.")
        print("  -> Make sure the WOPI page loaded in an iframe (not navigated away by GET).")
        print("  -> Verify wss://office.mcgeedan.com is reachable from the browser.")
        print(f"  -> Run: wscat -c 'wss://office.mcgeedan.com/doc/{effective_key}/c/?EIO=4&transport=websocket'")


if __name__ == "__main__":
    main()
