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

  options.graphide.enable = lib.mkEnableOption "the whole Graphide stack";

  config = lib.mkIf config.graphide.enable {
    graphide.network.enable  = lib.mkDefault true;
    graphide.registry.enable = lib.mkDefault true;
    graphide.auth.enable     = lib.mkDefault true;
    graphide.api.enable      = lib.mkDefault true;
    graphide.web.enable      = lib.mkDefault true;
    graphide.demo.enable     = lib.mkDefault true;
  };
}
