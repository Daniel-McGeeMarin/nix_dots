{ config, lib, ... }:
# The mcgeedan.com estate: blogs, dashboard, git forge, cloud storage, office,
# the personal site and the finance app.
#
# `serv.enable` is the master switch for all of it. Each service still has its
# own option so a host can opt out of one, but the default for every one of them
# follows the master -- so turning the estate off is a single line.
#
# What is deliberately NOT in here any more:
#   - sshd, the trusted tailnet interface and the never-sleep targets, which are
#     now system/headless. They kept the machine administrable and had no
#     business being tied to whether the blogs are running; with them here,
#     `serv.enable = false` was a lockout.
#   - podman and the auto-update timer, now system/podman.nix, because the
#     Graphide stack needs both and must not depend on the estate being on.
#   - the whole Graphide stack, now system/graphide. It shares a machine with
#     this and nothing else: its own domain, tunnel, Caddy and data.
{
  imports = [
    ./network.nix
    ./auth.nix
    ./dashboard.nix
    ./blogs.nix
    ./ocis.nix
    ./onlyoffice.nix
    ./apps.nix
    ./forgejo.nix
  ];

  options.serv.enable = lib.mkEnableOption "the whole mcgeedan.com service estate";

  # mkDefault throughout, so `serv.enable = true` turns everything on while a
  # host can still switch an individual service back off. Note this is a plain
  # default and not a hard binding: when serv.enable is false these options fall
  # back to their own `false`, so nothing here forces anything on.
  #
  # The graphide.* options are deliberately absent. They are moving to their own
  # tree and must not be coupled to this switch, or turning the estate off would
  # take the product stack down with it.
  config = lib.mkIf config.serv.enable {
    serv.network.enable    = lib.mkDefault true;
    serv.auth.enable       = lib.mkDefault true;
    serv.dashboard.enable  = lib.mkDefault true;
    serv.blogs.enable      = lib.mkDefault true;
    serv.ocis.enable       = lib.mkDefault true;
    serv.onlyoffice.enable = lib.mkDefault true;
    serv.apps.site.enable  = lib.mkDefault true;
    serv.forgejo.enable    = lib.mkDefault true;
  };
}
