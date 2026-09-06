{ config, lib, pkgs, ... }:
# The hackerboard: the wall board on the TV attached to this machine.
#
# Here rather than under hosts/ because it is a Graphide component and
# `graphide.*` is where a reader goes looking for one. It is, though, the one
# part of this directory that does *not* move with the stack -- it needs the
# physical screen, so it stays with whichever machine the TV is plugged into.
#
# Unlike every sibling, `enable` does not follow `graphide.enable`. The rest of
# the stack is headless services; this one paints a screen and wants speakers,
# and having it switch on as a side effect of turning the server stack on would
# be a surprise rather than a convenience.
#
# The board itself lives in the monorepo (`monolith/hackerboard/`) and is run
# through ../../dashboard.nix, which shells out to that checkout. What this
# module owns is the *configuration*, so the board is declared here like
# everything else on the machine rather than hand-edited into a dotfile.
#
# Secrets are the one thing that cannot be: `settings` ends up in the
# world-readable Nix store. The board takes `password_file` / `token_file`
# instead, which hold a path it reads at startup -- point those at agenix.
let
  cfg = config.graphide.hackerboard;
  format = pkgs.formats.toml { };
  dashboard = import ../../dashboard.nix {
    inherit pkgs;
    defaultSrc = cfg.srcDir;
  };
in
{
  options.graphide.hackerboard = {
    enable = lib.mkEnableOption "the hackerboard wall board and its `dashboard` launcher";

    srcDir = lib.mkOption {
      type = lib.types.str;
      default = "${config.graphide.demo.autoBuild.srcDir}/monolith";
      description = ''
        The monorepo checkout the launcher runs the board out of, baked into
        `dashboard` at build time.

        It defaults to the clone the demo autobuild already keeps current on
        this machine, which is the only monolith checkout the server has. That
        is a real coupling and worth knowing about: the board sees whatever
        that pipeline last synced, and the clone is root-owned. Point this
        somewhere else if you want the board independent of the demo build.

        GRAPHIDE_MONOLITH overrides it at run time.
      '';
    };

    settings = lib.mkOption {
      type = format.type;
      default = { };
      description = ''
        Rendered to /etc/hackerboard/config.toml, which the board loads ahead
        of any hand-edited copy in ~/.config -- so what is declared here is
        what is on the screen.

        The schema is the one documented in
        `monolith/hackerboard/config.example.toml`. Anything omitted keeps its
        default, and a tile whose connector is unconfigured renders as
        DISCONNECTED with a setup hint rather than erroring.

        Never put a password or token in here. Use the `_file` variants.
      '';
      example = lib.literalExpression ''
        {
          board.countdown_date = "2026-09-19";
          growth = { ok = 4.0; good = 7.0; target = 7.0; };
          github.repos = [ "GraphideHQ/monolith" ];
          proton = {
            user = "founders@graphide.net";
            password_file = config.age.secrets.hackerboard-proton.path;
          };
        }
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    # `tv-run dashboard` resolves this off PATH. See hosts/XiaServer/tv-seat.nix.
    environment.systemPackages = [ dashboard ];

    environment.etc."hackerboard/config.toml".source =
      format.generate "hackerboard-config.toml" cfg.settings;
  };
}
