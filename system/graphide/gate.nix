{ config, lib, pkgs, ... }:
# Invite-only gate in front of the demo boxes.
#
# Authelia cannot issue "open this URL and you are on demobox1, and only
# demobox1". That is the product requirement, so the boxes left Authelia and
# this process is the whole perimeter Caddy consults before it will proxy to
# a pod.
#
# Without secrets/graphide/gate-key.age the Caddy vhosts in demo.nix fail
# closed (401) rather than proxying. Missing the key must not leave a shell
# on the public internet. Create the file, git add it, rebuild, then:
#
#   graphide-demo-mint --box demobox1 --ttl 12h --label "press"
#
let
  cfg = config.graphide.gate;
  demo = config.graphide.demo;

  gateKeyFile = ../../secrets/graphide/gate-key.age;
  haveKey = builtins.pathExists gateKeyFile;

  gateBin = pkgs.writers.writePython3Bin "graphide-gate" {
    flakeIgnore = [ "E501" "W503" ];
  } (builtins.readFile ./gate.py);

  boxPorts = lib.concatMapStringsSep "," (s: "${s.name}:${toString s.port}")
    (lib.imap0 (i: name: { inherit name; port = demo.basePort + i; }) demo.sessions);

  mint = pkgs.writeShellApplication {
    name = "graphide-demo-mint";
    runtimeInputs = [ gateBin ];
    text = ''
      exec graphide-gate mint \
        --key-file ${config.age.secrets.graphide-gate-key.path} \
        --domain ${lib.escapeShellArg demo.domain} \
        --boxes ${lib.escapeShellArg (lib.concatStringsSep "," demo.sessions)} \
        "$@"
    '';
  };
in
{
  options.graphide.gate = {
    enable = lib.mkEnableOption "the signed-link gate in front of the demo boxes";

    hasKey = lib.mkOption {
      type = lib.types.bool;
      readOnly = true;
      default = haveKey;
      description = "Whether secrets/graphide/gate-key.age is in the flake. demo.nix 401s the boxes when this is false.";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 8011;
      description = "Loopback port Caddy forward_auth talks to. 8010 is website-api.";
    };
  };

  config = lib.mkIf cfg.enable {
    warnings = lib.optional (!haveKey) ''
      graphide.gate: secrets/graphide/gate-key.age is missing. Demo boxes will
      answer 401 until you create it (and git add it — flakes only see tracked
      files):

        PUBKEY=$(awk '{print $1" "$2}' /etc/ssh/ssh_host_ed25519_key.pub)
        KEY=$(od -A n -t x1 -N 32 /dev/urandom | tr -d ' \n')
        printf 'DEMO_GATE_KEY=%s\n' "$KEY" \
          | nix run nixpkgs#age -- -r "$PUBKEY" -o secrets/graphide/gate-key.age
        git add secrets/graphide/gate-key.age
    '';

    age.secrets = lib.optionalAttrs haveKey {
      graphide-gate-key = {
        file = gateKeyFile;
        mode = "0400";
        owner = "graphide-gate";
        group = "graphide-gate";
      };
    };

    users.users.graphide-gate = {
      isSystemUser = true;
      group = "graphide-gate";
    };
    users.groups.graphide-gate = { };

    systemd.tmpfiles.rules = [
      "d ${config.graphide.dataDir}/demo/gate 0750 graphide-gate graphide-gate -"
    ];

    environment.systemPackages = [ gateBin ] ++ lib.optionals haveKey [ mint ];

    systemd.services.graphide-gate = lib.mkIf haveKey {
      description = "Graphide demo magic-link gate";
      after = [ "agenix.service" ];
      wantedBy = [ "multi-user.target" ];
      before = [ "caddy-graphide.service" ];
      serviceConfig = {
        ExecStart = "${gateBin}/bin/graphide-gate serve";
        EnvironmentFile = config.age.secrets.graphide-gate-key.path;
        Environment = [
          "DEMO_DOMAIN=${demo.domain}"
          "DEMO_BOXES=${lib.concatStringsSep "," demo.sessions}"
          "DEMO_BOX_PORTS=${boxPorts}"
          "DEMO_GATE_LISTEN=127.0.0.1:${toString cfg.port}"
          "DEMO_GATE_STATE=${config.graphide.dataDir}/demo/gate/state.json"
          "DEMO_IDLE_GRACE=300"
        ];
        User = "graphide-gate";
        Group = "graphide-gate";
        Restart = "on-failure";
        RestartSec = "2s";
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        ReadWritePaths = [ "${config.graphide.dataDir}/demo/gate" ];
        RestrictAddressFamilies = [ "AF_INET" "AF_UNIX" ];
      };
    };
  };
}
