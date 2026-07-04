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
      ports   = [ "127.0.0.1:9200:9200" ];
      volumes = [ "/srv/data/ocis:/var/lib/ocis" ];
      environment = {
        OCIS_URL        = "https://cloud.mcgeedan.com";
        # Caddy terminates TLS; tell OCIS not to do its own
        OCIS_INSECURE   = "true";
        PROXY_HTTP_ADDR = "0.0.0.0:9200";
        PROXY_TLS       = "false";
        # Store generated config inside the volume so it survives restarts
        OCIS_CONFIG_DIR = "/var/lib/ocis/config";
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
      reverse_proxy 127.0.0.1:9200 {
        header_up X-Forwarded-Proto https
      }
      # Inject office.mcgeedan.com into OCIS's CSP frame-src so OnlyOffice iframes are allowed
      header Content-Security-Policy "https://embed\.diagrams\.net/" "https://embed.diagrams.net/ https://office.mcgeedan.com"
    '';
  };
}
