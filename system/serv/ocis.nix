{ config, lib, ... }:
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
          # flush_interval -1 forces immediate SSE byte flushing so OCIS's
          # keep-alive pings reach Cloudflare before its ~100s proxy timeout
          # fires a 524, which was breaking OnlyOffice context initialization.
          flush_interval -1
          header_up X-Forwarded-Proto https
          header_down Content-Security-Policy "https://embed\.diagrams\.net/" "https://embed.diagrams.net/ https://office.mcgeedan.com"
          header_down Content-Security-Policy "(connect-src[^;]*)" "$1 https://office.mcgeedan.com wss://office.mcgeedan.com"
        }
      }
    '';
  };
}
