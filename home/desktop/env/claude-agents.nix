{ config, lib, pkgs, ... }:
with lib;
let
  cfg = config.programs.claudeAgents;
  stateDir = "$XDG_RUNTIME_DIR/claude-agents";

  hookSessionStart = pkgs.writeShellApplication {
    name = "claude-agent-hook-session-start";
    runtimeInputs = [ pkgs.jq pkgs.coreutils ];
    text = ''
      input=$(cat)
      sid=$(printf '%s' "$input" | jq -r '.session_id // empty')
      [ -z "$sid" ] && exit 0
      mkdir -p "${stateDir}"
      printf 'idle' > "${stateDir}/$sid.state"
    '';
  };

  hookPreToolUse = pkgs.writeShellApplication {
    name = "claude-agent-hook-pre-tool-use";
    runtimeInputs = [ pkgs.jq pkgs.coreutils ];
    text = ''
      input=$(cat)
      sid=$(printf '%s' "$input" | jq -r '.session_id // empty')
      [ -z "$sid" ] && exit 0
      printf 'working' > "${stateDir}/$sid.state"
    '';
  };

  hookNotification = pkgs.writeShellApplication {
    name = "claude-agent-hook-notification";
    runtimeInputs = [ pkgs.jq pkgs.coreutils pkgs.libnotify ];
    text = ''
      input=$(cat)
      sid=$(printf '%s' "$input" | jq -r '.session_id // empty')
      msg=$(printf '%s' "$input" | jq -r '.message // "Agent needs attention"')
      [ -z "$sid" ] && exit 0
      printf 'needs-approval' > "${stateDir}/$sid.state"
      notify-send "Claude Agent" "$msg" --icon=terminal
    '';
  };

  hookStop = pkgs.writeShellApplication {
    name = "claude-agent-hook-stop";
    runtimeInputs = [ pkgs.jq pkgs.coreutils ];
    text = ''
      input=$(cat)
      sid=$(printf '%s' "$input" | jq -r '.session_id // empty')
      [ -z "$sid" ] && exit 0
      printf 'idle' > "${stateDir}/$sid.state"
    '';
  };

  watcher = pkgs.writeShellApplication {
    name = "claude-agents-watcher";
    runtimeInputs = with pkgs; [ inotify-tools jq hyprland coreutils ];
    text = ''
      mkdir -p "${stateDir}"

      move_window() {
        local sid="$1" workspace="$2" addr
        addr=$(hyprctl clients -j | jq -r --arg class "claude-agent-$sid" \
          '.[] | select(.class == $class) | .address' | head -1)
        [ -z "$addr" ] && return 0
        hyprctl dispatch movetoworkspacesilent "name:$workspace,address:$addr" >/dev/null
      }

      handle() {
        local sf="$1" sid state
        [[ "$sf" != *.state ]] && return 0
        [ -f "$sf" ] || return 0
        sid=$(basename "$sf" .state)
        state=$(cat "$sf")
        case "$state" in
          idle|working|needs-approval) move_window "$sid" "$state" ;;
        esac
      }

      for sf in "${stateDir}"/*.state; do
        [ -f "$sf" ] && handle "$sf"
      done

      inotifywait -m -e close_write,moved_to "${stateDir}" --format '%w%f' \
        | while read -r sf; do
            handle "$sf"
          done
    '';
  };

  spawner = pkgs.writeShellApplication {
    name = "claude-agent-spawn";
    runtimeInputs = [ pkgs.coreutils ];
    text = ''
      cwd="''${1:-$HOME}"
      sid="agent-$(date +%s%3N)"
      mkdir -p "${stateDir}"
      printf 'idle' > "${stateDir}/$sid.state"
      CLAUDE_AGENT_CLASS="$sid" ${pkgs.kitty}/bin/kitty \
        --class "claude-agent-$sid" \
        --working-directory "$cwd" \
        -e sh -c "${pkgs.claude-code}/bin/claude" &
    '';
  };

  picker = pkgs.writeShellApplication {
    name = "claude-agent-pick-and-spawn";
    runtimeInputs = [ pkgs.fzf pkgs.jq pkgs.hyprland pkgs.coreutils spawner ];
    text = ''
      agents=$(hyprctl clients -j | jq -r \
        '.[] | select(.class | startswith("claude-agent-"))
        | .class + " [" + .workspace.name + "]"')

      options="new agent"
      [ -n "$agents" ] && options="$agents
$options"

      choice=$(printf '%s' "$options" | fzf --prompt="Agent: " \
        --height=40% --reverse --no-sort) || true

      case "$choice" in
        "new agent")
          claude-agent-spawn "$HOME"
          ;;
        "")
          ;;
        *)
          cls=$(printf '%s' "$choice" | awk '{print $1}')
          addr=$(hyprctl clients -j | jq -r \
            --arg class "$cls" '.[] | select(.class == $class) | .address')
          [ -n "$addr" ] && hyprctl dispatch focuswindow "address:$addr" >/dev/null
          ;;
      esac
    '';
  };

in {
  options.programs.claudeAgents.enable =
    mkEnableOption "Claude Code agent management with Hyprland workspace integration";

  config = mkIf cfg.enable {
    home.packages = [ watcher spawner picker ];

    home.file.".claude/settings.json" = {
      force = true;
      text = builtins.toJSON {
        hooks = {
          SessionStart = [{
            matcher = "";
            hooks = [{ type = "command"; command = "${hookSessionStart}/bin/claude-agent-hook-session-start"; }];
          }];
          PreToolUse = [{
            matcher = "";
            hooks = [{ type = "command"; command = "${hookPreToolUse}/bin/claude-agent-hook-pre-tool-use"; }];
          }];
          Notification = [{
            matcher = "";
            hooks = [{ type = "command"; command = "${hookNotification}/bin/claude-agent-hook-notification"; }];
          }];
          Stop = [{
            matcher = "";
            hooks = [{ type = "command"; command = "${hookStop}/bin/claude-agent-hook-stop"; }];
          }];
        };
      };
    };

    systemd.user.services.claude-agents-watcher = {
      Unit = {
        Description = "Claude Code agent state watcher";
        After = [ "graphical-session.target" ];
        PartOf = [ "graphical-session.target" ];
      };
      Service = {
        Type = "simple";
        ExecStart = "${watcher}/bin/claude-agents-watcher";
        Restart = "on-failure";
        RestartSec = "2s";
      };
      Install.WantedBy = [ "graphical-session.target" ];
    };

    wayland.windowManager.hyprland = {
      plugins = [ pkgs.hyprlandPlugins.hyprexpo ];
      settings = {
        workspace = [
          "name:idle, persistent:true"
          "name:working, persistent:true"
          "name:needs-approval, persistent:true"
        ];
        windowrulev2 = [
          "float, class:^claude-agent-.*$"
          "size 80% 80%, class:^claude-agent-.*$"
          "center, class:^claude-agent-.*$"
        ];
        bind = [
          "SUPER, D, submap, claude-agents"
        ];
        plugin.hyprexpo = {
          columns = 3;
          gap_size = 4;
          bg_col = "rgba(111111ff)";
          workspace_method = "center current";
          enable_gesture = false;
        };
      };
      extraConfig = ''
        submap = claude-agents
        bind = , 1, workspace, name:idle
        bind = , 2, workspace, name:working
        bind = , 3, workspace, name:needs-approval
        bind = SHIFT, 1, movetoworkspace, name:idle
        bind = SHIFT, 2, movetoworkspace, name:working
        bind = SHIFT, 3, movetoworkspace, name:needs-approval
        bind = , T, exec, ${picker}/bin/claude-agent-pick-and-spawn
        bind = , O, exec, hyprctl dispatch hyprexpo:expo toggle
        bind = , F, fullscreen, 1
        bind = , G, togglegroup
        bind = SHIFT, G, moveoutofgroup
        bind = , bracketleft, changegroupactive, b
        bind = , bracketright, changegroupactive, f
        bind = , escape, submap, reset
        submap = reset
      '';
    };
  };
}
