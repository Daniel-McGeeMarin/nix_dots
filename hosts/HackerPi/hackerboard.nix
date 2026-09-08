# The hackerboard as a headless LAN service, plus its self-updater.
#
# Two sources of truth coexist here, by design:
#
#   baked    the monolith flake input pins a rev; its web bundle and API
#            source are built into the image, so the board works on first
#            boot with no network and no credentials.
#   live     a sparse, blobless clone of the monolith under
#            /var/lib/hackerboard/src -- only hackerboard/'s blobs are ever
#            fetched, which is what keeps a 200 MB monorepo down to a few MB
#            on the Pi. The updater timer maintains it and repoints the
#            api-root / web-dist symlinks at it.
#
# The service reads through those symlinks, so "which build is live" is a
# filesystem fact, not a config option, and the updater switching them is
# atomic per symlink. Until a deploy key is provisioned at
# /var/lib/hackerboard/deploy-key the updater exits quietly and the baked
# build serves forever -- a missing secret degrades to "stale", not "down".
#
# Python dependencies (fastapi, uvicorn, ...) come from the *baked* rev even
# when the live checkout is newer: the interpreter environment is a store
# path, and rebuilding it on-device would mean evaluating nixpkgs on a Pi 3.
# If hackerboard ever grows a new Python dependency, update the monolith
# input and redeploy the system instead.
{ config, lib, pkgs, inputs, ... }:

let
  hb = import "${inputs.monolith}/hackerboard/nix" { inherit pkgs; };
  dataDir = "/var/lib/hackerboard";
  srcDir = "${dataDir}/src";

  settingsFormat = pkgs.formats.toml { };
  boardConfig = settingsFormat.generate "hackerboard-config.toml" {
    board = {
      title = "GRAPHIDE";
      subtitle = "HACKERBOARD";
    };
    # No speakers and no mpv on this box; the tile would only ever say
    # DISCONNECTED, so it is off outright.
    music.enabled = false;
  };

  updater = pkgs.writeShellApplication {
    name = "hackerboard-update";
    runtimeInputs = [ pkgs.git pkgs.nix pkgs.openssh config.systemd.package ];
    text = ''
      key=${dataDir}/deploy-key
      if [ ! -f "$key" ]; then
        echo "hackerboard-update: no deploy key at $key; keeping the baked build"
        exit 0
      fi
      export GIT_SSH_COMMAND="ssh -i $key -o IdentitiesOnly=yes -o UserKnownHostsFile=${dataDir}/known_hosts -o StrictHostKeyChecking=accept-new"

      if [ ! -d ${srcDir}/.git ]; then
        git clone --filter=blob:none --sparse --branch master \
          git@github.com:GraphideHQ/monolith.git ${srcDir}
        git -C ${srcDir} sparse-checkout set hackerboard
        old=none
      else
        old=$(git -C ${srcDir} rev-parse HEAD)
        git -C ${srcDir} fetch --quiet origin master
        git -C ${srcDir} reset --hard --quiet origin/master
      fi
      new=$(git -C ${srcDir} rev-parse HEAD)

      # Repoint even when the rev is unchanged if the links still aim at the
      # baked build -- that is the first successful run after provisioning.
      if [ "$old" = "$new" ] \
         && [ "$(readlink ${dataDir}/api-root)" = "${srcDir}/hackerboard/api" ]; then
        exit 0
      fi

      echo "hackerboard-update: $old -> $new, rebuilding the web bundle"
      # nix-build both builds and leaves a GC root at web-dist, so the live
      # bundle can never be garbage-collected out from under the server.
      # <nixpkgs> is pinned to the system's own nixpkgs via nix.nixPath, so
      # this is a cache hit for everything but the bundle itself.
      nix-build --out-link ${dataDir}/web-dist \
        -E "(import ${srcDir}/hackerboard/nix { pkgs = import <nixpkgs> { }; }).web"
      ln -sfn ${srcDir}/hackerboard/api ${dataDir}/api-root
      systemctl restart hackerboard.service
      echo "hackerboard-update: now serving $new"
    '';
  };
in
{
  users.users.hackerboard = {
    isSystemUser = true;
    group = "hackerboard";
  };
  users.groups.hackerboard = { };

  # The board reads this ahead of any hand-edited copy (config.py's
  # SYSTEM_CONFIG), so what is declared here is what is on the screen.
  environment.etc."hackerboard/config.toml".source = boardConfig;

  systemd.tmpfiles.rules = [
    "d ${dataDir} 0755 root root -"
    "d ${dataDir}/data 0750 hackerboard hackerboard -"
    # 'L' creates these only when nothing is there yet: first boot serves the
    # baked build, and a later updater repoint survives reboots and rebuilds.
    "L ${dataDir}/web-dist - - - - ${hb.web}"
    "L ${dataDir}/api-root - - - - ${hb.api}/lib"
  ];

  systemd.services.hackerboard = {
    description = "hackerboard LAN server";
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" ];
    environment = {
      HACKERBOARD_HOST = "0.0.0.0";
      HACKERBOARD_PORT = "8420";
      HACKERBOARD_DATA_DIR = "${dataDir}/data";
      HACKERBOARD_WEB_DIST = "${dataDir}/web-dist";
      PYTHONPATH = "${dataDir}/api-root";
    };
    serviceConfig = {
      User = "hackerboard";
      Group = "hackerboard";
      ExecStart = "${hb.pythonEnv}/bin/python -m hackerboard.main";
      Restart = "on-failure";
      RestartSec = 5;

      # The process serves company data on a box on a shelf; give it as
      # little of the system as it needs. It reads the store, the symlinks
      # and the checkout, and writes only its own data dir.
      NoNewPrivileges = true;
      PrivateTmp = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      ReadWritePaths = [ "${dataDir}/data" ];
      ProtectKernelTunables = true;
      ProtectKernelModules = true;
      ProtectControlGroups = true;
      RestrictAddressFamilies = [ "AF_INET" "AF_INET6" "AF_UNIX" ];
      RestrictNamespaces = true;
      LockPersonality = true;
      CapabilityBoundingSet = [ "" ];
      SystemCallFilter = [ "@system-service" ];
    };
  };

  systemd.services.hackerboard-update = {
    description = "pull the hackerboard from GitHub and swap it in";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${updater}/bin/hackerboard-update";
      # Echo update activity to the console as well as the journal: a Pi with
      # a TV plugged in shows what the updater did without anyone SSHing in.
      StandardOutput = "journal+console";
      StandardError = "journal+console";
    };
  };
  systemd.timers.hackerboard-update = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "5min";
      OnUnitActiveSec = "15min";
      RandomizedDelaySec = "2min";
    };
  };

  # `hackerboard-update` at a shell for a manual pull; the timer runs the
  # same script.
  environment.systemPackages = [ updater ];

  # Make <nixpkgs> on the device mean the flake-pinned nixpkgs this system
  # was built from, so the updater's nix-build agrees with the image instead
  # of chasing a channel.
  nix.registry.nixpkgs.flake = inputs.nixpkgs;
  nix.nixPath = [ "nixpkgs=flake:nixpkgs" ];
}
