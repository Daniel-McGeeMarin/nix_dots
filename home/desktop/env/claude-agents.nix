{ config, lib, pkgs, ... }:
with lib;
let
  cfg = config.programs.claudeAgents;
  stateDir = "$XDG_RUNTIME_DIR/claude-agents";

  # ── Hooks ────────────────────────────────────────────────────────────────────

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

  # ── Watcher (repositions all windows whenever any state file changes) ────────

  watcher = pkgs.writeShellApplication {
    name = "claude-agents-watcher";
    runtimeInputs = with pkgs; [ inotify-tools jq hyprland gawk coreutils ];
    text = ''
      mkdir -p "${stateDir}"

      reposition_all() {
        local mon mw mh scale ox oy lw lh col_w
        mon=$(hyprctl monitors -j | jq 'map(select(.focused))[0] // .[0]')
        mw=$(printf '%s' "$mon" | jq '.width')
        mh=$(printf '%s' "$mon" | jq '.height')
        scale=$(printf '%s' "$mon" | jq '.scale')
        # reserved = [left, top, right, bottom] in logical pixels (already scaled)
        ox=$(printf '%s' "$mon" | jq '.reserved[0]')
        oy=$(printf '%s' "$mon" | jq '.reserved[1]')
        local res_right res_bottom
        res_right=$(printf '%s' "$mon" | jq '.reserved[2]')
        res_bottom=$(printf '%s' "$mon" | jq '.reserved[3]')
        lw=$(awk "BEGIN{printf \"%d\", $mw/$scale - $ox - $res_right}")
        lh=$(awk "BEGIN{printf \"%d\", $mh/$scale - $oy - $res_bottom}")
        col_w=$(( lw / 3 ))

        local idle_addrs=() working_addrs=() approval_addrs=()
        local sf sid state addr
        for sf in "${stateDir}"/*.state; do
          [ -f "$sf" ] || continue
          sid=$(basename "$sf" .state)
          state=$(cat "$sf")
          addr=$(hyprctl clients -j | jq -r --arg c "claude-agent-$sid" \
            '.[] | select(.class == $c) | .address' | head -1)
          [ -z "$addr" ] && continue
          case "$state" in
            idle)           idle_addrs+=("$addr") ;;
            working)        working_addrs+=("$addr") ;;
            needs-approval) approval_addrs+=("$addr") ;;
          esac
        done

        # layout_col <col_x> [addr ...]
        layout_col() {
          local cx="$1"; shift
          local n="$#"
          [ "$n" -eq 0 ] && return 0
          local wh=$(( lh / n ))
          local i=0 addr
          for addr in "$@"; do
            local wy=$(( oy + i * wh ))
            hyprctl dispatch movetoworkspacesilent "special:claude-agents,address:$addr" >/dev/null 2>&1 || true
            hyprctl dispatch movewindowpixel "exact $cx $wy,address:$addr" >/dev/null 2>&1 || true
            hyprctl dispatch resizewindowpixel "exact $col_w $wh,address:$addr" >/dev/null 2>&1 || true
            i=$(( i + 1 ))
          done
        }

        [ "''${#idle_addrs[@]}"     -gt 0 ] && layout_col "$(( ox ))"             "''${idle_addrs[@]}"
        [ "''${#working_addrs[@]}"  -gt 0 ] && layout_col "$(( ox + col_w ))"     "''${working_addrs[@]}"
        [ "''${#approval_addrs[@]}" -gt 0 ] && layout_col "$(( ox + col_w*2 ))"   "''${approval_addrs[@]}"
      }

      reposition_all

      inotifywait -m -e close_write,moved_to "${stateDir}" --format '%w%f' \
        | while read -r sf; do
            [[ "$sf" == *.state ]] && reposition_all
          done
    '';
  };

  # ── Spawner ──────────────────────────────────────────────────────────────────

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

  # ── SUPER+O: spawn — only fires inside the overlay ───────────────────────────

  overlayCheck = "hyprctl monitors -j | jq -e 'any(.[]; .focused == true and .specialWorkspace.name == \"special:claude-agents\")' >/dev/null 2>&1";

  smartO = pkgs.writeShellApplication {
    name = "claude-agents-smart-o";
    runtimeInputs = [ pkgs.jq pkgs.hyprland spawner ];
    text = ''
      if ${overlayCheck}; then
        claude-agent-spawn "$HOME"
      fi
    '';
  };

  smartP = pkgs.writeShellApplication {
    name = "claude-agents-smart-p";
    runtimeInputs = [ pkgs.jq pkgs.hyprland ];
    text = ''
      if ${overlayCheck}; then
        hyprctl dispatch fullscreen 1
      fi
    '';
  };

in {
  options.programs.claudeAgents.enable =
    mkEnableOption "Claude Code agent management with Hyprland workspace integration";

  config = mkIf cfg.enable {
    home.packages = [ watcher spawner smartO smartP ];

    home.file.".claude/settings.json" = {
      force = true;
      text = builtins.toJSON {
        hooks = {
          SessionStart = [{ matcher = ""; hooks = [{ type = "command"; command = "${hookSessionStart}/bin/claude-agent-hook-session-start"; }]; }];
          PreToolUse   = [{ matcher = ""; hooks = [{ type = "command"; command = "${hookPreToolUse}/bin/claude-agent-hook-pre-tool-use"; }]; }];
          Notification = [{ matcher = ""; hooks = [{ type = "command"; command = "${hookNotification}/bin/claude-agent-hook-notification"; }]; }];
          Stop         = [{ matcher = ""; hooks = [{ type = "command"; command = "${hookStop}/bin/claude-agent-hook-stop"; }]; }];
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
      settings = {
        windowrulev2 = [
          # All claude CLI windows float and land in the overlay workspace
          "float, class:^claude-agent-.*$"
          "workspace special:claude-agents silent, class:^claude-agent-.*$"
        ];
        bind = [
          "SUPER, D, togglespecialworkspace, claude-agents"
          "SUPER, O, exec, ${smartO}/bin/claude-agents-smart-o"
          "SUPER, P, exec, ${smartP}/bin/claude-agents-smart-p"
        ];
      };
    };
  };
}
