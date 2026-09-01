{ config, lib, pkgs, ... }:
# One `podman login ghcr.io` at boot, so any container in this tree can pull
# from the private registry.
#
# Its own file because both web.nix and demo.nix order themselves behind this
# unit, and it used to live inside api.nix -- which meant the marketing site and
# the demo pods had a hard dependency on the API server module being enabled for
# a reason that had nothing to do with the API server.
#
# The credential is a classic GitHub PAT with read:packages and no expiry.
# The login is global to root's containers/auth.json and persists across
# reboots, which is why a missing ordering dependency here looks like it works
# for months and then fails exactly once, on a first boot or after the auth file
# is wiped.
let
  cfg = config.graphide.registry;
in
{
  options.graphide.registry = {
    enable = lib.mkEnableOption "Podman login to the Graphide GHCR registry";

    username = lib.mkOption {
      type = lib.types.str;
      default = "Daniel-McGeeMarin";
      description = "GitHub account the read:packages token belongs to.";
    };
  };

  config = lib.mkIf cfg.enable {
    age.secrets.ghcr-token = {
      file = ../../secrets/graphide/ghcr-token.age;
      mode = "0400";
    };

    systemd.services.graphide-ghcr-login = {
      description = "Authenticate Podman with GHCR";
      after = [ "agenix.service" "network-online.target" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];
      script = ''
        ${pkgs.podman}/bin/podman login ghcr.io \
          --username ${cfg.username} \
          --password-stdin < ${config.age.secrets.ghcr-token.path}
      '';
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
    };
  };
}
