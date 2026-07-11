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
      labels = { "io.containers.autoupdate" = "registry"; };
    };

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
