{ config, lib, ... }:
{
  options.serv.onlyoffice.enable = lib.mkEnableOption "OnlyOffice document server + OCIS collaboration bridge";

  config = lib.mkIf config.serv.onlyoffice.enable {
    systemd.tmpfiles.rules = [
      "d /srv/data/onlyoffice 0755 root root"
    ];

    virtualisation.oci-containers.containers = {
      onlyoffice = {
        image   = "docker.io/onlyoffice/documentserver:latest";
        ports   = [ "127.0.0.1:8090:80" ];
        volumes = [ "/srv/data/onlyoffice:/var/www/onlyoffice/Data" ];
        environment = {
          WOPI_ENABLED = "true";
          JWT_ENABLED  = "false";
        };
        labels = { "io.containers.autoupdate" = "registry"; };
      };

      # Runs as a sidecar to the main ocis container; bridges OCIS ↔ OnlyOffice via WOPI.
      # ocis server does not start the collaboration service — it must be run separately.
      # Shares ocis's network namespace so it can reach NATS on 127.0.0.1:9233 directly;
      # OnlyOffice reaches the WOPI HTTP on ocis:9300 (same IP as the ocis container).
      ocis-collab = {
        image        = "docker.io/owncloud/ocis:latest";
        cmd          = [ "collaboration" "server" ];
        dependsOn    = [ "ocis" ];
        volumes      = [ "/srv/data/ocis:/var/lib/ocis:ro" ];
        extraOptions = [ "--network=container:ocis" ];
        environment  = {
          OCIS_CONFIG_DIR                           = "/var/lib/ocis/config";
          COLLABORATION_GRPC_ADDR                   = "0.0.0.0:9301";
          COLLABORATION_HTTP_ADDR                   = "0.0.0.0:9300";
          MICRO_REGISTRY                            = "nats-js-kv";
          MICRO_REGISTRY_ADDRESS                    = "127.0.0.1:9233";
          # WOPI src must be an https:// URL — OnlyOffice 8+ silently refuses http:// sources.
          # The OCIS proxy routes /wopi/ to the collab service, so the external URL works.
          COLLABORATION_WOPI_SRC                    = "https://cloud.mcgeedan.com";
          COLLABORATION_APP_NAME                    = "OnlyOffice";
          COLLABORATION_APP_PRODUCT                 = "OnlyOffice";
          COLLABORATION_APP_ADDR                    = "https://office.mcgeedan.com";
          COLLABORATION_APP_ICON                    = "https://office.mcgeedan.com/web-apps/apps/documenteditor/main/resources/img/favicon.ico";
          COLLABORATION_APP_INSECURE                = "false";
          COLLABORATION_CS3API_DATAGATEWAY_INSECURE = "true";
          OCIS_URL                                  = "https://cloud.mcgeedan.com";
          OCIS_LOG_LEVEL                            = "debug";
          OCIS_LOG_PRETTY                           = "true";
        };
        labels = { "io.containers.autoupdate" = "registry"; };
      };
    };

    # ocis-collab fails on first boot if OCIS hasn't finished initializing NATS/gateway yet.
    # Allow longer retry window with a pause between attempts so it recovers automatically.
    systemd.services."podman-ocis-collab" = {
      serviceConfig = {
        RestartSec = "15s";
      };
      unitConfig = {
        StartLimitBurst       = 20;
        StartLimitIntervalSec = 600;
      };
    };

    # No require_auth — OnlyOffice iframes are opened directly by OCIS with a WOPI token in
    # the URL; inserting Authelia here would break the editor flow. WOPI tokens are the gate.
    # X-Forwarded-Proto https is required so OnlyOffice generates https:// action URLs
    # in its WOPI discovery endpoint — without it OCIS gets http:// URLs which the
    # browser's CSP frame-src blocks and the browser warns about mixed content.
    services.caddy.virtualHosts."http://office.mcgeedan.com".extraConfig = ''
      reverse_proxy 127.0.0.1:8090 {
        header_up X-Forwarded-Proto https
      }
    '';
  };
}
