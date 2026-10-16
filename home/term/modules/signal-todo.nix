{ config, lib, pkgs, ... }:
# `signal-todo`: send the TODO markdown file as a Signal DM, by hand only.
# There is deliberately no timer -- Dan does not want a daily reminder, so
# nothing here ever sends on its own.
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
    runtimeInputs = [ signal-cli pkgs.coreutils ];
    text = ''
      export SIGNAL_TODO_FILE=${lib.escapeShellArg cfg.todoFile}
      export SIGNAL_TODO_SECTIONS=${lib.escapeShellArg (lib.concatStringsSep "|" cfg.sections)}
    '' + builtins.readFile ./signal-todo.sh;
  };
in
{
  options.signalTodo = {
    enable = lib.mkEnableOption "the `signal-todo` command (manual send of the TODO file)";

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
  };

  config = lib.mkIf cfg.enable {
    # signal-cli on PATH for linking and relinking; qrencode to show the link QR.
    home.packages = [ script signal-cli pkgs.qrencode ];
  };
}
