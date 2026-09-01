{ config, lib, pkgs, ... }:
# Graphide's own ingress: its Cloudflare tunnel and its own Caddy.
#
# == Why a second Caddy rather than more vhosts on the shared one ==
#
# Caddy parses its whole config as one unit, so a mistake anywhere takes the
# process down with it -- graphide-web.nix already carried a comment about
# exactly that ("an undefined snippet is a Caddy config parse error that takes
# down every other vhost with it"). With one process, a bad Graphide route
# 502s the blogs, and vice versa. Two processes make that impossible.
#
# It also makes the stack liftable: this file plus its siblings and one tunnel
# token are the whole ingress story. Nothing here reads anything from
# system/serv.
#
# The cost is that nixpkgs' services.caddy is a singleton -- it has no
# `instances` option -- so this is a hand-written unit and a Caddyfile assembled
# by Nix. The one thing the NixOS module gives you that a hand-rolled unit does
# not is config validation, so that is bought back explicitly: the Caddyfile is
# run through `caddy validate` in a derivation, which means a broken route fails
# `nixos-rebuild` rather than leaving a dead unit at 3am.
let
  cfg = config.graphide.network;

  # Indent every line of a contributed block, not just the first. Without this
  # the generated file is technically valid and unreadable, which matters
  # because it is what you `cat` when a route misbehaves.
  indentLines = prefix: text:
    lib.concatStringsSep "\n"
      (map (l: if l == "" then "" else prefix + l)
        (lib.splitString "\n" (lib.removeSuffix "\n" text)));

  siteBlocks = lib.concatStringsSep "\n\n" (lib.mapAttrsToList
    (host: v: "${host} {\n${indentLines "  " v.extraConfig}\n}")
    cfg.virtualHosts);

  # Global options, then snippets, then sites -- Caddyfile requires that order.
  #
  # auto_https off + http_port: there is no TLS here at all. Cloudflare
  # terminates it and the tunnel hands us plain HTTP, so every site address is
  # http:// and binds the one port below. Without auto_https off, Caddy would
  # try to get certificates for hostnames it cannot validate.
  caddyfileText = ''
    {
      admin off
      auto_https off
      http_port ${toString cfg.port}
      default_bind 127.0.0.1
    }

    ${cfg.extraConfig}

    ${siteBlocks}
  '';

  rawCaddyfile = pkgs.writeText "graphide-caddyfile-raw" caddyfileText;

  caddyfile = pkgs.runCommand "graphide-Caddyfile"
    { nativeBuildInputs = [ pkgs.caddy ]; }
    ''
      cp ${rawCaddyfile} $out
      # caddy writes to these while provisioning; without them it tries $HOME,
      # which does not exist in the build sandbox.
      export XDG_CONFIG_HOME="$TMPDIR/config"
      export XDG_DATA_HOME="$TMPDIR/data"
      caddy validate --adapter caddyfile --config $out
    '';
in
{
  options.graphide.network = {
    enable = lib.mkEnableOption "Graphide's Cloudflare tunnel and its own Caddy";

    port = lib.mkOption {
      type = lib.types.port;
      default = 8081;
      description = ''
        Loopback port this Caddy listens on. The Graphide Cloudflare tunnel must
        point its ingress here rather than at :80, which is the shared Caddy.

        Changing this is a two-sided change: the tunnel's ingress rule lives in
        the Cloudflare dashboard, not in this repo.
      '';
    };

    virtualHosts = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule {
        options.extraConfig = lib.mkOption {
          type = lib.types.lines;
          default = "";
        };
      });
      default = { };
      example = lib.literalExpression ''{ "http://graphide.net".extraConfig = "reverse_proxy 127.0.0.1:3003"; }'';
      description = ''
        Deliberately the same shape as services.caddy.virtualHosts, so the
        service modules in this tree read the same as the ones in system/serv
        and moving a route between them is a one-word change.
      '';
    };

    extraConfig = lib.mkOption {
      type = lib.types.lines;
      default = "";
      description = ''
        Caddyfile snippets, emitted between the global options block and the
        site blocks. This is where (require_auth) and friends are defined.
      '';
    };

    configFile = lib.mkOption {
      type = lib.types.path;
      readOnly = true;
      default = caddyfile;
      defaultText = lib.literalMD "the generated, validated Caddyfile";
      description = ''
        The Caddyfile this instance runs, after `caddy validate` has passed on
        it. Read-only, and exposed rather than hidden in a `let` so the config
        is inspectable without deploying:

        ```
        nix build .#nixosConfigurations.XiaServer.config.graphide.network.configFile
        cat result
        ```

        Building that path is also the cheapest way to check a route change,
        since the validation runs as part of the build.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    # The graphide.net tunnel. Its sibling for mcgeedan.com stays in
    # system/serv/network.nix; the two accounts, the two tokens and now the two
    # Caddys are entirely separate.
    #
    # Secret format is one line: TUNNEL_TOKEN=<token from the Cloudflare dashboard>
    age.secrets.cloudflare-tunnel-graphide = {
      file = ../../secrets/cloudflare-tunnel-graphide.age;
      owner = "cloudflared";
    };

    # The cloudflared user is declared here as well as in system/serv/network.nix
    # -- mkDefault on both so either module can run alone without colliding with
    # the other. That is what lets serv be switched off entirely.
    users.users.cloudflared = {
      isSystemUser = lib.mkDefault true;
      group = lib.mkDefault "cloudflared";
    };
    users.groups.cloudflared = { };

    systemd.services.cloudflared-graphide = {
      description = "Cloudflare Tunnel (graphide account)";
      after = [ "network-online.target" "agenix.service" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        EnvironmentFile = config.age.secrets.cloudflare-tunnel-graphide.path;
        ExecStart = "${pkgs.cloudflared}/bin/cloudflared tunnel --no-autoupdate run";
        Restart = "on-failure";
        RestartSec = "5s";
        User = "cloudflared";
        Group = "cloudflared";
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = true;
      };
    };

    # Its own user rather than reusing services.caddy's: that user only exists
    # when the shared Caddy is enabled, and this must run when it is not.
    users.users.graphide-caddy = {
      isSystemUser = true;
      group = "graphide-caddy";
    };
    users.groups.graphide-caddy = { };

    systemd.services.caddy-graphide = {
      description = "Caddy reverse proxy for the Graphide stack";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];
      # A config error cannot reach here -- the Caddyfile above is validated at
      # build time -- so a failure of this unit means a runtime problem, not a
      # typo.
      serviceConfig = {
        ExecStart = "${pkgs.caddy}/bin/caddy run --config ${cfg.configFile} --adapter caddyfile";
        ExecReload = "${pkgs.caddy}/bin/caddy reload --config ${cfg.configFile} --adapter caddyfile --force";
        User = "graphide-caddy";
        Group = "graphide-caddy";
        Restart = "on-failure";
        RestartSec = "5s";
        StateDirectory = "caddy-graphide";
        Environment = [
          "XDG_DATA_HOME=/var/lib/caddy-graphide"
          "XDG_CONFIG_HOME=/var/lib/caddy-graphide"
        ];
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = true;
      };
    };
  };
}
