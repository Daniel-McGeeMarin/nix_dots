{ config, lib, pkgs, ... }:
{
  config = {
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
    #
    # Compiled from the .gitignore files actually in use across ~/Documents/Projects
    # (JS/Node, Python, Java/Gradle, .NET, IDE metadata) — anything that's a
    # dependency, build output, or cache and therefore already reproducible without
    # needing a cloud copy. Deliberately NOT excluding .git: that's the one thing in
    # a repo worth having a second copy of if a git host ever gets locked out.
    xdg.configFile."ownCloud/sync-exclude.lst".text = ''
      # JS / Node
      node_modules
      dist
      build
      .next
      .nuxt
      .vercel
      .pnp
      .pnp.js
      .yarn
      playwright-report
      test-results
      *.tsbuildinfo
      *.log
      yarn-error.log*
      yarn-debug.log*
      npm-debug.log*

      # Python
      .venv
      venv
      ENV
      venv.bak
      __pycache__
      .pytest_cache
      .mypy_cache
      .pytype
      .pybuilder
      __pypackages__
      .tox
      .nox
      .hypothesis
      .scrapy
      .ipynb_checkpoints
      cython_debug
      .eggs
      eggs
      develop-eggs
      *.egg
      *.egg-info
      *.pyc
      *.pyo
      *$py.class
      *.so
      htmlcov
      .coverage
      .coverage.*
      coverage.xml
      MANIFEST
      db.sqlite3
      db.sqlite3-journal
      celerybeat.pid
      celerybeat-schedule
      .dmypy.json
      dmypy.json

      # Java/Gradle, .NET, misc build caches
      target
      .settings
      .project
      nbproject
      nbbuild
      nbdist
      .sts4-cache
      .springBeans

      # IDE metadata
      .idea
      .vscode

      # Rust
      .cache
    '';
  };
}
