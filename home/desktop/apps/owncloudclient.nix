{ config, lib, pkgs, ... }:
{
  config = lib.mkIf config.desktop.enable {
    # Note: owncloud.cfg's default maxChunkSize (100000000 bytes) collides with
    # Cloudflare's 100MB request body limit on the tunnel path, causing intermittent
    # checksum-mismatch/retry loops. Set maxChunkSize=52428800 (50MB) in
    # ~/.config/ownCloud/owncloud.cfg under [General] after install/login. Don't
    # nix-manage the whole file — it also holds live account/folder/sync state.
    home.packages = with pkgs; [ owncloud-client ];

    # sync-exclude.lst is pure declarative input (client only reads it, never writes
    # back), unlike owncloud.cfg, so it's safe to manage fully here. These are on top
    # of the client's own built-in default list (lockfiles, .DS_Store, etc.) — patterns
    # without a "/" match the name at any depth, so "node_modules" excludes every
    # node_modules dir in the sync tree, not just top-level ones.
    xdg.configFile."ownCloud/sync-exclude.lst".text = ''
      node_modules
      .venv
      venv
      __pycache__
      .git
    '';
  };
}
