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
        # Gaps: 24px between columns (section divider feel), 8px between stacked windows
        local col_gap=24 win_gap=8
        col_w=$(( (lw - 2*col_gap) / 3 ))

        local clients_json
        clients_json=$(hyprctl clients -j)

        local idle_pairs="" working_pairs="" approval_pairs=""
        local sf sid state client title addr
        for sf in "${stateDir}"/*.state; do
          [ -f "$sf" ] || continue
          sid=$(basename "$sf" .state)
          state=$(cat "$sf")
          client=$(printf '%s' "$clients_json" | jq -r --arg c "claude-agent-$sid" \
            '.[] | select(.class == $c) | [.title, .address] | join("\t")' | head -1)
          [ -z "$client" ] && continue
          title=$(printf '%s' "$client" | cut -f1)
          addr=$(printf '%s' "$client" | cut -f2)
          case "$state" in
            idle)           idle_pairs+="$title"$'\t'"$addr"$'\n' ;;
            working)        working_pairs+="$title"$'\t'"$addr"$'\n' ;;
            needs-approval) approval_pairs+="$title"$'\t'"$addr"$'\n' ;;
          esac
        done

        # Sort each column by title, extract addresses into arrays
        local idle_addrs=() working_addrs=() approval_addrs=()
        [ -n "$idle_pairs" ]    && readarray -t idle_addrs    < <(printf '%s' "$idle_pairs"    | sort -f | cut -f2)
        [ -n "$working_pairs" ] && readarray -t working_addrs < <(printf '%s' "$working_pairs" | sort -f | cut -f2)
        [ -n "$approval_pairs" ] && readarray -t approval_addrs < <(printf '%s' "$approval_pairs" | sort -f | cut -f2)

        # layout_col <col_x> [addr ...]
        layout_col() {
          local cx="$1"; shift
          local n="$#"
          [ "$n" -eq 0 ] && return 0
          # Distribute win_gap between windows; last window gets no trailing gap
          local wh=$(( (lh - (n-1)*win_gap) / n ))
          local i=0 addr
          for addr in "$@"; do
            local wy=$(( oy + i * (wh + win_gap) ))
            hyprctl dispatch movetoworkspacesilent "special:claude-agents,address:$addr" >/dev/null 2>&1 || true
            hyprctl dispatch movewindowpixel "exact $cx $wy,address:$addr" >/dev/null 2>&1 || true
            hyprctl dispatch resizewindowpixel "exact $col_w $wh,address:$addr" >/dev/null 2>&1 || true
            i=$(( i + 1 ))
          done
        }

        [ "''${#idle_addrs[@]}"     -gt 0 ] && layout_col "$(( ox ))"                          "''${idle_addrs[@]}"
        [ "''${#working_addrs[@]}"  -gt 0 ] && layout_col "$(( ox + col_w + col_gap ))"        "''${working_addrs[@]}"
        [ "''${#approval_addrs[@]}" -gt 0 ] && layout_col "$(( ox + 2*(col_w + col_gap) ))"    "''${approval_addrs[@]}"
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
      title=$(basename "$cwd")
      CLAUDE_AGENT_CLASS="$sid" ${pkgs.kitty}/bin/kitty \
        --class "claude-agent-$sid" \
        --title "$title" \
        --working-directory "$cwd" \
        --override tab_bar_min_tabs=1 \
        --override tab_bar_edge=top \
        --override tab_bar_style=separator \
        --override tab_title_template="{title}" \
        -e sh -c "${pkgs.claude-code}/bin/claude" &
    '';
  };

  overlayCheck = "hyprctl monitors -j | jq -e 'any(.[]; .focused == true and .specialWorkspace.name == \"special:claude-agents\")' >/dev/null 2>&1";

  # ── SUPER+O: fuzzy picker — focus running agent or spawn in chosen dir ───────

  smartO = pkgs.writeShellApplication {
    name = "claude-agents-smart-o";
    runtimeInputs = [ pkgs.jq pkgs.hyprland pkgs.fzf pkgs.fd pkgs.coreutils spawner ];
    text = ''
      history_file="''${XDG_STATE_HOME:-$HOME/.local/state}/claude-agents/dir-history"
      mkdir -p "$(dirname "$history_file")"

      # Running agents: "▶\tTITLE (STATE)\tCLASS"
      running=$(hyprctl clients -j | jq -r '
        .[] | select(.class | startswith("claude-agent-"))
        | ["▶", (.title + " [" + .workspace.name + "]"), .class]
        | join("\t")
      ')

      # Dirs: history (◆) + git repos from Documents/nixos only, deduped
      dirs=$(
        {
          [ -f "$history_file" ] && awk '{print "◆\t" $0 "\t" $0}' "$history_file"
          {
            [ -d "$HOME/Documents" ] && \
              fd -H -t d -d 5 '^\.git$' "$HOME/Documents" 2>/dev/null | sed 's|/\.git$||'
            [ -d "$HOME/nixos" ] && \
              fd -H -t d -d 5 '^\.git$' "$HOME/nixos" 2>/dev/null | sed 's|/\.git$||'
          } | awk '{print "\t" $0 "\t" $0}'
        } \
        | awk -F'\t' '!seen[$3]++'
      )

      all=$(printf '%s\n%s' "$running" "$dirs" | grep -v '^$')

      choice=$(printf '%s' "$all" \
        | fzf --delimiter=$'\t' --with-nth=1,2 \
              --prompt='Claude › ' --height=50% --reverse \
              --preview='[ -d {3} ] && ls -- {3} || echo "(running agent)"' \
              --preview-window=right:35%)

      [ -z "$choice" ] && exit 0

      tag=$(printf '%s' "$choice" | cut -f1)
      data=$(printf '%s' "$choice" | cut -f3)

      if [ "$tag" = "▶" ]; then
        # Focus the running agent window
        addr=$(hyprctl clients -j | jq -r --arg cls "$data" \
          '.[] | select(.class == $cls) | .address')
        [ -n "$addr" ] && hyprctl dispatch focuswindow "address:$addr" >/dev/null
      else
        # Record to history and spawn
        { echo "$data"; cat "$history_file" 2>/dev/null; } \
          | awk '!seen[$0]++' | head -50 > "''${history_file}.tmp"
        mv "''${history_file}.tmp" "$history_file"
        claude-agent-spawn "$data"
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
