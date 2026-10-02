{ config, lib, pkgs, ... }:
# Daily Signal reminder: sends a TODO markdown file as a DM, at most once a
# day, the first time Signal Desktop is seen running that day. Nothing goes
# out until `signal-todo` has been run by hand once (that run sends and arms
# the timer).
#
# Sending uses signal-cli linked as an extra device on the phone's account
# (`signal-cli link -n <name>`, scan the QR from Settings -> Linked devices).
# Signal Desktop itself has no CLI to send from.
#
# signal-cli comes from pkgs.unstable on purpose: Signal's servers refuse
# linked devices from old clients (0.14.2 from stable nixpkgs got a 409 on
# link, 2026-10-01), and ai-cli-autoupdate re-pins nixpkgs-unstable daily.
#
# The account and recipient numbers live in ~/.config/signal-todo/env
# (ACCOUNT=, and RECIPIENT= or GROUP_ID=), outside this public repo.
let
  cfg = config.signalTodo;
  signal-cli = pkgs.unstable.signal-cli;
  script = pkgs.writeShellApplication {
    name = "signal-todo";
    runtimeInputs = [ signal-cli pkgs.coreutils pkgs.procps pkgs.util-linux ];
    text = ''
      export SIGNAL_TODO_FILE=${lib.escapeShellArg cfg.todoFile}
      export SIGNAL_TODO_SECTIONS=${lib.escapeShellArg (lib.concatStringsSep "|" cfg.sections)}
    '' + builtins.readFile ./signal-todo.sh;
  };
in
{
  options.signalTodo = {
    enable = lib.mkEnableOption "the daily Signal TODO reminder";

    todoFile = lib.mkOption {
      type = lib.types.str;
      default = "${config.home.homeDirectory}/Documents/startup/Graphide/docs/TODO.md";
      description = "Markdown file sent as the message body.";
    };

    sections = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "Dan" "Ben" ];
      description = "The \"## \" headings whose sections are sent; the rest of the file (e.g. Long term) is left out.";
    };

    checkEvery = lib.mkOption {
      type = lib.types.str;
      default = "*:0/10";
      description = "OnCalendar for the check; each check sends only if today's message is still due and Signal is open.";
    };
  };

  config = lib.mkIf cfg.enable {
    # signal-cli on PATH for linking and relinking; qrencode to show the link QR.
    home.packages = [ script signal-cli pkgs.qrencode ];

    systemd.user.services.signal-todo = {
      Unit.Description = "Send the TODO file to Signal (at most once a day, only while Signal is open)";
      Service = {
        Type = "oneshot";
        ExecStart = "${lib.getExe script} --auto";
      };
    };

    systemd.user.timers.signal-todo = {
      Unit.Description = "Check whether today's Signal TODO still needs sending";
      Timer = {
        OnBootSec = "2min";
        OnCalendar = cfg.checkEvery;
      };
      Install.WantedBy = [ "timers.target" ];
    };
  };
}
