{ config, lib, pkgs, inputs, osConfig, ... }:

{
  # Both halves of the user environment. XiaServer imports only ../../home/term;
  # the desktop tree is not a flag any more, it is this line.
  imports = [
    ../../home/term
    ../../home/desktop
    inputs.graphide-tools.homeManagerModules.accounts
    inputs.graphide-tools.homeManagerModules.transcripts
  ];

  programs.home-manager.enable = true;
  home.username = "xia";
  home.homeDirectory = "/home/xia";

  programming.enable = true;
  ai.enable = false;
  ai.claudeCode.enable = true;
  ai.cursorCli.enable = true;
  ai.codex.enable = true;
  ai.autoUpdate.enable = true;
  ai.privatellm.enable = true;

  graphide.enable = true;
  # The release build on PATH, not gr-dev. Since 2026-09-14 a checkout-channel
  # gr refuses the host daemon socket (monolith grug/daemonclient/channel.go),
  # so a gr-dev `gr claude` launched Claude Code with no Graphide integration
  # and every other daemon command failed the same way.
  graphide.variant = "prod";
  # Auto-update timer turned off 2026-09-17 (Dan): rebuild manually with
  # `graphide-autoupdate` instead of a 30m background timer. See the monolith's
  # nix/home-manager/graphide.nix for why the update script stays on PATH.
  graphide.autoUpdate.enable = false;
  # Where the tarball has always lived on this machine, rather than the
  # module's XDG default, so the existing download is reused.
  graphide.gredTarball = "${config.home.homeDirectory}/MyApps/graphide-dist/graphide-linux-x64.tar.gz";
  programs.claudeAgents.enable = true;
  # Ben's account system (monolith utilities/scripts/accounts): graphide-claude
  # and graphide-codex wrappers pick an account per new launch, and a watcher
  # keeps the 5h/7d usage the shell's Accounts panel shows. It replaces Orca's
  # and claude-swap's in-place credential swapping. The wrappers exec the real
  # vendor binaries by absolute path so nothing can loop back into them.
  services.graphide-accounts = {
    enable = true;
    claudeCommand = "${config.home.profileDirectory}/bin/claude";
    codexCommand = "${config.home.profileDirectory}/bin/codex";
  };

  # Every 15 min, copy Claude Code / Codex / Cursor transcripts to XiaServer's
  # never-deleting library (monolith utilities/scripts/transcripts). Offline
  # XiaServer is a quiet no-op; the next run catches up.
  services.graphide-transcripts.enable = true;

  desktop = {
    gaming.enable = true;
    workmic.enable = true;
  };

  home.packages = [
    pkgs.nix-output-monitor
    (pkgs.calibre.overrideAttrs
      (attrs: {
        preFixup = (
          builtins.replaceStrings
            [
              ''
                --prefix PYTHONPATH : $PYTHONPATH \
              ''
            ]
            [
              ''
                --prefix LD_LIBRARY_PATH : ${pkgs.libressl.out}/lib \
                --prefix PYTHONPATH : $PYTHONPATH \
              ''
            ]
            attrs.preFixup
        );
      }))
  ];

  programs = {
    password-store.enable = true;
    rbw.enable = true;
  };

  # The plain OpenSSH agent: it offers only keys actually loaded, so a locked
  # key is skipped rather than waited on. ~/.ssh/config's AddKeysToAgent loads
  # id_ed25519_server after its passphrase is typed once per login.
  services.ssh-agent.enable = true;
  systemd.user.sessionVariables.SSH_AUTH_SOCK = "/run/user/1000/ssh-agent";
  home.stateVersion = "23.11"; # Do not change
}
