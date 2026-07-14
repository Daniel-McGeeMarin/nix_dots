{ config, lib, ... }:
# ============================================================================
# WARNING — OnlyOffice + browser adblockers
# ----------------------------------------------------------------------------
# BEFORE debugging any "OnlyOffice editor shows UI shell but no document"
# issue on the server, RULE OUT THE CLIENT-SIDE ADBLOCKER FIRST.
#
# uBlock Origin (and most privacy extensions: AdGuard, Privacy Badger,
# Malwarebytes Browser Guard) inject content scripts that intercept iframe
# creation and can silently break the OnlyOffice editor with no server-side
# error. Symptoms:
#   - The editor menu/toolbar renders fine.
#   - No /doc/{key}/c/ Socket.IO request ever appears in OnlyOffice's
#     nginx access log (podman-onlyoffice systemd journal).
#   - Browser console shows "iframe protection loop" from a content.js.
#   - Everything works in an incognito/private window (no extensions).
#
# Fix: whitelist BOTH cloud.mcgeedan.com AND office.mcgeedan.com in the
# adblocker. Confirmed working 2026-07-14 after full server-side stack was
# already correct (CSP, SSE keepalive, X-Forwarded-Proto, WOPI collab).
#
# Server-side warnings for this stack live in-file below (search for WARNING).
# See also: home/desktop/apps/firefox.nix (near ublock-origin entry).
# ============================================================================
{
  options.serv.ocis.enable = lib.mkEnableOption "ownCloud Infinite Scale";

  config = lib.mkIf config.serv.ocis.enable {
    age.secrets.ocis-admin-password = {
      file = ../../secrets/ocis-admin-password.age;
      mode = "0444";
    };

    systemd.tmpfiles.rules = [
      "d /srv/data/ocis 0750 1000 1000"
    ];

    virtualisation.oci-containers.containers.ocis = {
      image   = "docker.io/owncloud/ocis:latest";
      ports   = [ "127.0.0.1:9200:9200" "127.0.0.1:9300:9300" ];
      volumes = [ "/srv/data/ocis:/var/lib/ocis" ];
      environment = {
        OCIS_URL        = "https://cloud.mcgeedan.com";
        # Caddy terminates TLS; tell OCIS not to do its own
        OCIS_INSECURE   = "true";
        PROXY_HTTP_ADDR = "0.0.0.0:9200";
        PROXY_TLS       = "false";
        # Store generated config inside the volume so it survives restarts
        OCIS_CONFIG_DIR = "/var/lib/ocis/config";
        # activitylog can't keep up with its own NATS queue during bulk uploads,
        # causing "slow consumer" message drops and failed upload postprocessing
        # (ERR_UPLOAD_NOT_FOUND) -> client sees checksum mismatches and retries
        # whole files. Known upstream bug: owncloud/ocis#10825
        OCIS_EXCLUDE_RUN_SERVICES = "activitylog";
        # Cloudflare kills idle HTTP connections at ~100s. OCIS's SSE keepalive
        # defaults to 0s (disabled), so the notifications stream sits silent and
        # gets 524'd — OCIS web then waits forever on `sseAuthenticated` before
        # posting the WOPI context to the OnlyOffice iframe, so the editor never
        # loads. Added in ocis v7.0.0 for exactly this reason.
        SSE_KEEPALIVE_INTERVAL = "30s";
      };
      environmentFiles = [ config.age.secrets.ocis-admin-password.path ];
      # ocis init generates jwt/signing secrets on first run; || true skips if already done
      entrypoint = "/bin/sh";
      cmd        = [ "-c" "ocis init || true; ocis server" ];
      # All OIDC calls (discovery, JWKS, userinfo, SSE auth) go to cloud.mcgeedan.com
      # which DNS-resolves to Cloudflare externally, causing a hairpin through the tunnel
      # that times out. host-gateway (10.88.0.1) routes them to Caddy on the host directly.
      # ocis-collab inherits this via --network=container:ocis.
      extraOptions = [ "--add-host=cloud.mcgeedan.com:host-gateway" ];
      labels = { "io.containers.autoupdate" = "registry"; };
    };

    # Allow the OCIS container to reach Caddy's internal HTTPS vhost on 10.88.0.1:443.
    # The NixOS firewall drops packets from the Podman subnet by default, causing the
    # OIDC discovery / JWKS fetch to time out with "context deadline exceeded".
    # This only opens port 443 on podman0 — external interfaces are unaffected.
    networking.firewall.interfaces."podman0".allowedTCPPorts = [ 443 ];

    # Internal HTTPS endpoint for the OCIS container's own OIDC calls.
    # Bound only to the Podman gateway (10.88.0.1) so external traffic is unaffected.
    # OCIS routes cloud.mcgeedan.com here via --add-host instead of hairpinning through
    # Cloudflare. tls internal uses Caddy's built-in CA; OCIS_INSECURE=true accepts it.
    services.caddy.virtualHosts."https://cloud.mcgeedan.com".extraConfig = ''
      bind 10.88.0.1
      tls internal
      handle /wopi/* {
        reverse_proxy 127.0.0.1:9300 {
          header_up X-Forwarded-Proto https
        }
      }
      handle {
        reverse_proxy 127.0.0.1:9200 {
          flush_interval -1
          header_up X-Forwarded-Proto https
        }
      }
    '';

    # No require_auth — OCIS uses its own OIDC auth; Authelia here would break
    # desktop/mobile sync clients that authenticate directly with OCIS.
    services.caddy.virtualHosts."http://cloud.mcgeedan.com".extraConfig = ''
      # WOPI callbacks from OnlyOffice go directly to the collab service (9300).
      # The OCIS proxy (9200) serves its SPA for unknown paths and does not route
      # /wopi/ internally — requests there return 200 HTML, which OnlyOffice rejects.
      handle /wopi/* {
        reverse_proxy 127.0.0.1:9300 {
          header_up X-Forwarded-Proto https
        }
      }
      handle {
        reverse_proxy 127.0.0.1:9200 {
          # flush_interval -1 forwards SSE bytes to the client the instant OCIS
          # emits them (no Caddy-side buffering). Pairs with SSE_KEEPALIVE_INTERVAL
          # on the ocis container so heartbeats actually reach Cloudflare before
          # its ~100s idle-timeout fires a 524.
          flush_interval -1
          header_up X-Forwarded-Proto https
          # OCIS's default CSP allows office.mcgeedan.com nowhere. OnlyOffice needs
          # to load into an iframe (frame-src) + fetch/websocket (connect-src) + show
          # its app favicon in the OCIS file list (img-src). The api.js loaded in the
          # OCIS page context uses eval() (script-src 'unsafe-eval') and loads fonts as
          # base64 data: URIs (font-src data:). worker-src is for the service worker
          # OnlyOffice 9.x registers for offline mode.
          header_down Content-Security-Policy "https://embed\.diagrams\.net/" "https://embed.diagrams.net/ https://office.mcgeedan.com"
          header_down Content-Security-Policy "(connect-src[^;]*)" "$1 https://office.mcgeedan.com wss://office.mcgeedan.com"
          header_down Content-Security-Policy "(img-src[^;]*)" "$1 https://office.mcgeedan.com"
          header_down Content-Security-Policy "(script-src[^;]*)" "$1 'unsafe-eval' https://office.mcgeedan.com"
          header_down Content-Security-Policy "(font-src[^;]*)" "$1 data: https://office.mcgeedan.com"
          header_down Content-Security-Policy "(child-src[^;]*)" "$1 https://office.mcgeedan.com blob:"
        }
      }
    '';
  };
}
