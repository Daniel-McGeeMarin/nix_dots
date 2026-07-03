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
      ocis-collab = {
        image      = "docker.io/owncloud/ocis:latest";
        cmd        = [ "collaboration" "server" ];
        dependsOn  = [ "ocis" ];
        environment = {
          COLLABORATION_GRPC_ADDR                   = "0.0.0.0:9301";
          COLLABORATION_HTTP_ADDR                   = "0.0.0.0:9300";
          # Reach OCIS's embedded NATS via Podman DNS (container name resolution)
          MICRO_REGISTRY                            = "nats-js-kv";
          MICRO_REGISTRY_ADDRESS                    = "ocis:9233";
          # OnlyOffice calls back to this URL for WOPI file operations
          COLLABORATION_WOPI_SRC                    = "http://ocis-collab:9300";
          COLLABORATION_APP_NAME                    = "OnlyOffice";
          COLLABORATION_APP_PRODUCT                 = "OnlyOffice";
          COLLABORATION_APP_ADDR                    = "https://office.mcgeedan.com";
          COLLABORATION_APP_ICON                    = "https://office.mcgeedan.com/web-apps/apps/documenteditor/main/resources/img/favicon.ico";
          # Caddy handles TLS; internal OCIS WOPI endpoint is plain HTTP
          COLLABORATION_APP_INSECURE                = "false";
          COLLABORATION_CS3API_DATAGATEWAY_INSECURE = "true";
          OCIS_URL                                  = "https://cloud.mcgeedan.com";
        };
        labels = { "io.containers.autoupdate" = "registry"; };
      };
    };

    # No require_auth — OnlyOffice iframes are opened directly by OCIS with a WOPI token in
    # the URL; inserting Authelia here would break the editor flow. WOPI tokens are the gate.
    services.caddy.virtualHosts."http://office.mcgeedan.com".extraConfig = ''
      reverse_proxy 127.0.0.1:8090
    '';
  };
}
