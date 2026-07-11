#!/usr/bin/env python3
"""
OnlyOffice WOPI flow diagnostic.

How to get the WOPI action URL:
  1. Open OCIS in your browser and click a .docx file to open it.
  2. Open DevTools → Network tab (filter: "wopi").
  3. Find the POST request to office.mcgeedan.com/hosting/wopi/...
     (it will have WOPISrc=... and access_token=... in the URL).
  4. Right-click → Copy → Copy link address.
  5. Run: python3 test-wopi.py '<pasted-url>'

The token expires in ~10 minutes, so grab it quickly.
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


def post_wopi_action(url):
    req = urllib.request.Request(url, data=b"", method="POST")
    req.add_header("Content-Type", "application/x-www-form-urlencoded")
    req.add_header("User-Agent", "Mozilla/5.0 (WOPI-test)")
    req.add_header("Accept", "text/html,application/xhtml+xml")
    with urllib.request.urlopen(req, timeout=20) as resp:
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
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)

    url = sys.argv[1]
    print("=" * 60)
    print("STEP 1: POST to OnlyOffice WOPI action endpoint")
    print("=" * 60)
    print(f"URL: {url[:120]}{'...' if len(url) > 120 else ''}")
    print()

    try:
        status, html = post_wopi_action(url)
    except Exception as e:
        print(f"FAILED: {e}")
        sys.exit(1)

    print(f"HTTP {status} — got {len(html)} bytes of HTML")
    print()

    # --- Extract key fields ---
    key_data      = parse_field(html, "keyData")
    file_info_raw = parse_field(html, "fileInfoJsonData")
    config_raw    = parse_field(html, "docsApiConfigJsonData")
    user_auth_raw = parse_field(html, "userAuthJsonData")

    js_status_m = re.search(r'var statusCode\s*=\s*"([^"]*)"', html)
    js_status   = js_status_m.group(1) if js_status_m else "(not found)"

    print("=" * 60)
    print("STEP 2: Check critical page fields")
    print("=" * 60)

    # statusCode
    if js_status == "":
        print(f"[OK]  statusCode = '' (token accepted)")
    else:
        print(f"[BAD] statusCode = '{js_status}' — token rejected. Editor will show error & never call DocsAPI.DocEditor.")

    # keyData
    if key_data:
        print(f"[OK]  keyData = '{key_data[:60]}{'...' if len(key_data) > 60 else ''}'")
    else:
        print(f"[BAD] keyData = empty — docservice key not set. Socket.IO will never connect.")

    # fileInfoJsonData
    if file_info_raw and file_info_raw != "{}":
        try:
            fi = json.loads(file_info_raw)
            bn = fi.get("BaseFileName", "MISSING")
            print(f"[OK]  fileInfoJsonData.BaseFileName = '{bn}'")
        except Exception:
            print(f"[BAD] fileInfoJsonData invalid JSON: {file_info_raw[:80]}")
    else:
        print(f"[BAD] fileInfoJsonData = empty/{{}} — CheckFileInfo did not populate.")

    # docsApiConfigJsonData
    doc_key = None
    if config_raw and config_raw != "{}":
        try:
            cfg = json.loads(config_raw)
            doc_key = cfg.get("document", {}).get("key")
            title   = cfg.get("document", {}).get("title", "?")
            mode    = cfg.get("editorConfig", {}).get("mode", "?")
            print(f"[OK]  docsApiConfigJsonData: key={doc_key}, title={title}, mode={mode}")
        except Exception:
            print(f"[BAD] docsApiConfigJsonData invalid JSON")
    else:
        print(f"[BAD] docsApiConfigJsonData = empty/{{}} — editor config not built.")

    # Effective key (fall back to config if keyData div is empty)
    effective_key = key_data or doc_key
    print()

    # --- Direct CheckFileInfo test ---
    print("=" * 60)
    print("STEP 3: Direct CheckFileInfo call (bypasses OnlyOffice)")
    print("=" * 60)
    parsed = urllib.parse.urlparse(url)
    qs     = urllib.parse.parse_qs(parsed.query)
    wopi_src     = qs.get("WOPISrc",     [None])[0]
    access_token = qs.get("access_token",[None])[0]

    if wopi_src and access_token:
        print(f"WOPISrc:      {wopi_src}")
        print(f"access_token: {access_token[:30]}...")
        try:
            cfi_status, cfi_body = check_file_info(wopi_src, access_token)
            if cfi_status == 200:
                try:
                    info = json.loads(cfi_body)
                    print(f"[OK]  CheckFileInfo HTTP {cfi_status}: BaseFileName={info.get('BaseFileName')}, Size={info.get('Size')}")
                except Exception:
                    print(f"HTTP {cfi_status}: (non-JSON) {cfi_body[:120]}")
            else:
                print(f"[BAD] CheckFileInfo HTTP {cfi_status}: {cfi_body[:120]}")
        except Exception as e:
            print(f"[ERR] {e}")
    else:
        print("[SKIP] Could not extract WOPISrc/access_token from URL")
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
            print("      This means the docservice is not reachable at 127.0.0.1:8090/doc/{key}/c/")
    else:
        print("[SKIP] No docservice key found — cannot test Socket.IO")
    print()

    # --- Summary ---
    print("=" * 60)
    print("DIAGNOSIS")
    print("=" * 60)
    if js_status != "":
        print("Root cause: token rejected by OnlyOffice (statusCode non-empty).")
        print("  -> The access_token from the URL was invalid or expired.")
        print("  -> Try grabbing a fresh URL from browser DevTools immediately after clicking a file.")
    elif not (file_info_raw and file_info_raw != "{}"):
        print("Root cause: fileInfoJsonData is empty.")
        print("  -> OnlyOffice got statusCode=OK but could not fetch CheckFileInfo.")
        print("  -> Check: does OnlyOffice container resolve cloud.mcgeedan.com?")
        print("  -> Check: does /wopi/files/{id} return 200 JSON from inside the container?")
        print("  -> Run: sudo podman exec onlyoffice curl -s '<WOPISrc>?access_token=<token>'")
    elif not effective_key:
        print("Root cause: docservice key is empty despite valid token + fileInfo.")
        print("  -> This is unusual. OnlyOffice built the page but skipped the key.")
        print("  -> Check: /var/log/onlyoffice/documentserver/docservice.log for errors")
    else:
        print("All server-side fields look correct.")
        print("  -> The issue is in-browser JS execution after DocsAPI.DocEditor() is called.")
        print("  -> Check browser Console for JS errors when opening a file.")
        print("  -> Check: is wss://office.mcgeedan.com reachable from your browser?")
        print("  -> Run: wscat -c 'wss://office.mcgeedan.com/doc/{key}/c/?EIO=4&transport=websocket'")


if __name__ == "__main__":
    main()
