{ config, lib, ... }:
# The Graphide stack: the API server, the marketing site, and the demo boxes.
#
# Deliberately a sibling of system/serv rather than a subdirectory of it. The
# two share a machine and nothing else -- different domain, different Cloudflare
# account, different tunnel, its own Caddy, and (once the demo gate lands) its
# own auth. The intent is that moving this stack to a machine of its own is
# copying this directory, secrets/graphide/, and one ZFS dataset.
#
# `graphide.enable` is the master switch. Each service keeps its own option so
# one can be turned off individually, but the default follows the master.
#
# The single thread still tying this to system/serv is Authelia; see the header
# of ./auth.nix, which is the only file that touches it.
{
  imports = [
    ./network.nix
    ./registry.nix
    ./auth.nix
    ./api.nix
    ./web.nix
    ./demo.nix
  ];

  options.graphide = {
    enable = lib.mkEnableOption "the whole Graphide stack";

    dataDir = lib.mkOption {
      type = lib.types.str;
      default = "/srv/graphide";
      description = ''
        Everything this stack persists lives under here, and every path in the
        tree is derived from it. One root rather than directories scattered
        through /srv/data next to the estate's, because the point of the split
        is that the stack can be lifted onto another machine -- and with its own
        ZFS dataset mounted here, that is one `zfs send` rather than picking
        directories out of a shared dataset by hand.

        Changing this does NOT move any data. The contents have to be copied
        across first, with ownership preserved: postgres runs as uid 70 and the
        demo pods as uid 1000, and rootful podman means those are host uids.
      '';
    };
  };

  config = lib.mkIf config.graphide.enable {
    # The root itself. Each module creates its own subdirectories with the
    # ownership its container needs; this just guarantees the parent exists
    # whether or not it is a ZFS mountpoint yet.
    systemd.tmpfiles.rules = [ "d ${config.graphide.dataDir} 0755 root root -" ];

    graphide.network.enable  = lib.mkDefault true;
    graphide.registry.enable = lib.mkDefault true;
    graphide.auth.enable     = lib.mkDefault true;
    graphide.api.enable      = lib.mkDefault true;
    graphide.web.enable      = lib.mkDefault true;
    graphide.demo.enable     = lib.mkDefault true;
  };
}
