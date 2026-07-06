{ config, lib, pkgs, ... }:
with lib;
let
  cfg = config.programs.claudeAgents;
  stateDir = "$XDG_RUNTIME_DIR/claude-agents";

  # ── Hooks ────────────────────────────────────────────────────────────────────
  # State machine: idle → working (UserPromptSubmit) → needs-approval (Notification)
  #                          ↑____________ (PostToolUse = approved, PostToolUseFailure = denied)
  # Stop always → idle. No PreToolUse — fires before the permission dialog
  # and races with Notification.

  hookSessionStart = pkgs.writeShellApplication {
    name = "claude-agent-hook-session-start";
    runtimeInputs = [ pkgs.jq pkgs.coreutils ];
    text = ''
      input=$(cat)
      claude_sid=$(printf '%s' "$input" | jq -r '.session_id // empty')
      [ -z "$claude_sid" ] && exit 0
      agent_sid="''${CLAUDE_AGENT_SID:-$claude_sid}"
      mkdir -p "${stateDir}"
      printf 'idle' > "${stateDir}/$agent_sid.state"
    '';
  };

  hookUserPromptSubmit = pkgs.writeShellApplication {
    name = "claude-agent-hook-user-prompt-submit";
    runtimeInputs = [ pkgs.jq pkgs.coreutils ];
    text = ''
      input=$(cat)
      claude_sid=$(printf '%s' "$input" | jq -r '.session_id // empty')
      [ -z "$claude_sid" ] && exit 0
      agent_sid="''${CLAUDE_AGENT_SID:-$claude_sid}"
      printf 'working' > "${stateDir}/$agent_sid.state"
    '';
  };

  hookNotification = pkgs.writeShellApplication {
    name = "claude-agent-hook-notification";
    runtimeInputs = [ pkgs.jq pkgs.coreutils pkgs.libnotify ];
    text = ''
      input=$(cat)
      claude_sid=$(printf '%s' "$input" | jq -r '.session_id // empty')
      [ -z "$claude_sid" ] && exit 0
      agent_sid="''${CLAUDE_AGENT_SID:-$claude_sid}"
      msg=$(printf '%s' "$input" | jq -r '.message // "Agent needs attention"')
      printf 'needs-approval' > "${stateDir}/$agent_sid.state"
      notify-send "Claude Agent" "$msg" --icon=terminal
    '';
  };

  hookPostToolUse = pkgs.writeShellApplication {
    name = "claude-agent-hook-post-tool-use";
    runtimeInputs = [ pkgs.jq pkgs.coreutils ];
    text = ''
      input=$(cat)
      claude_sid=$(printf '%s' "$input" | jq -r '.session_id // empty')
      [ -z "$claude_sid" ] && exit 0
      agent_sid="''${CLAUDE_AGENT_SID:-$claude_sid}"
      printf 'working' > "${stateDir}/$agent_sid.state"
    '';
  };

  hookPostToolUseFailure = pkgs.writeShellApplication {
    name = "claude-agent-hook-post-tool-use-failure";
    runtimeInputs = [ pkgs.jq pkgs.coreutils ];
    text = ''
      input=$(cat)
      claude_sid=$(printf '%s' "$input" | jq -r '.session_id // empty')
      [ -z "$claude_sid" ] && exit 0
      agent_sid="''${CLAUDE_AGENT_SID:-$claude_sid}"
      printf 'working' > "${stateDir}/$agent_sid.state"
    '';
  };

  hookStop = pkgs.writeShellApplication {
    name = "claude-agent-hook-stop";
    runtimeInputs = [ pkgs.jq pkgs.coreutils ];
    text = ''
      input=$(cat)
      claude_sid=$(printf '%s' "$input" | jq -r '.session_id // empty')
      [ -z "$claude_sid" ] && exit 0
      agent_sid="''${CLAUDE_AGENT_SID:-$claude_sid}"
      printf 'idle' > "${stateDir}/$agent_sid.state"
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

        [ "''${#idle_addrs[@]}"     -gt 0 ] && layout_col "$(( ox ))"                          "''${idle_addrs[@]}"     || true
        [ "''${#working_addrs[@]}"  -gt 0 ] && layout_col "$(( ox + col_w + col_gap ))"        "''${working_addrs[@]}"  || true
        [ "''${#approval_addrs[@]}" -gt 0 ] && layout_col "$(( ox + 2*(col_w + col_gap) ))"    "''${approval_addrs[@]}" || true
      }

      reposition_all

      inotifywait -m -e close_write,moved_to "${stateDir}" --format '%w%f' \
        | while read -r sf; do
            [[ "$sf" == *.state ]] && reposition_all || true
          done
    '';
  };

  # ── Spawner ──────────────────────────────────────────────────────────────────

  spawner = pkgs.writeShellApplication {
    name = "claude-agent-spawn";
    runtimeInputs = [ pkgs.coreutils pkgs.util-linux ];
    text = ''
      cwd="''${1:-$HOME}"
      sid="agent-$(date +%s%3N)"
      mkdir -p "${stateDir}"
      printf 'idle' > "${stateDir}/$sid.state"
      printf '%s' "$cwd" > "${stateDir}/$sid.dir"
      title=$(basename "$cwd")
      CLAUDE_AGENT_SID="$sid" setsid --fork ${pkgs.kitty}/bin/kitty \
        --class "claude-agent-$sid" \
        --title "$title" \
        --working-directory "$cwd" \
        --override tab_bar_min_tabs=1 \
        --override tab_bar_edge=top \
        --override tab_bar_style=separator \
        --override tab_title_template="{title}" \
        -e "${pkgs.claude-code}/bin/claude"
    '';
  };

  overlayCheck = "hyprctl monitors -j | jq -e 'any(.[]; .focused == true and .specialWorkspace.name == \"special:claude-agents\")' >/dev/null 2>&1";

  # ── SUPER+O: fuzzy picker — focus running agent or spawn in chosen dir ───────

  smartO = pkgs.writeShellApplication {
    name = "claude-agents-smart-o";
    runtimeInputs = [ pkgs.jq pkgs.hyprland pkgs.fzf pkgs.fd pkgs.coreutils spawner ];
    text = ''
      # Show overlay first if not already visible
      if ! hyprctl monitors -j | jq -e 'any(.[]; .focused == true and .specialWorkspace.name == "special:claude-agents")' >/dev/null 2>&1; then
        hyprctl dispatch togglespecialworkspace claude-agents >/dev/null 2>&1
      fi

      history_file="''${XDG_STATE_HOME:-$HOME/.local/state}/claude-agents/dir-history"
      mkdir -p "$(dirname "$history_file")"

      GRN=$'\033[32m'
      YLW=$'\033[33m'
      CYN=$'\033[36m'
      DIM=$'\033[2m'
      RST=$'\033[0m'

      # Running agents — cyan ▶, field4=running
      running=$(hyprctl clients -j | jq -r '
        .[] | select(.class | startswith("claude-agent-"))
        | [.title + " [" + .workspace.name + "]", .class]
        | join("\t")
      ' | awk -v c="$CYN" -v r="$RST" -F'\t' \
          '{print c "▶" r "\t" c $1 r "\t" $2 "\trunning"}')

      # Git repos from Documents (depth 5) — green, field4=git
      git_repos=""
      if [ -d "$HOME/Documents" ]; then
        git_repos=$(fd -H -t d -d 5 '^\.git$' "$HOME/Documents" \
          -x dirname 2>/dev/null | sort -u)
      fi

      # All dirs in Documents up to depth 4, skipping .git internals
      top_dirs=""
      if [ -d "$HOME/Documents" ]; then
        top_dirs=$(fd -t d -d 4 --exclude '.git' . "$HOME/Documents" 2>/dev/null | sort -u)
      fi

      # Non-git dirs = dirs not equal to or underneath any git repo root
      non_git=""
      if [ -n "$top_dirs" ]; then
        if [ -n "$git_repos" ]; then
          non_git=$(printf '%s\n' "$top_dirs" | awk -v repos="$git_repos" '
            BEGIN { n=split(repos,r,"\n"); for(i=1;i<=n;i++) if(r[i]!="") g[r[i]]=1 }
            { for(repo in g) if($0==repo || index($0,repo "/")==1) next; print }
          ')
        else
          non_git="$top_dirs"
        fi
      fi

      dirs=$(
        {
          # History — yellow ◆
          [ -f "$history_file" ] && \
            awk -v c="$YLW" -v r="$RST" \
              '{print c "◆" r "\t" c $0 r "\t" $0 "\thistory"}' "$history_file"

          # Git repos — green "git"
          [ -n "$git_repos" ] && \
            printf '%s\n' "$git_repos" | \
            awk -v c="$GRN" -v r="$RST" \
              '{print c " git" r "\t" c $0 r "\t" $0 "\tgit"}'

          # Regular dirs — dim "dir"
          [ -n "$non_git" ] && \
            printf '%s\n' "$non_git" | \
            awk -v c="$DIM" -v r="$RST" \
              '{print c " dir" r "\t" c $0 r "\t" $0 "\tdir"}'
        } | awk -F'\t' '!seen[$3]++'
      )

      all=$(printf '%s\n%s' "$running" "$dirs" | grep -v '^$')

      # shellcheck disable=SC2016
      choice=$(printf '%s' "$all" \
        | fzf --ansi --delimiter=$'\t' --with-nth=1,2 \
              --prompt='Claude › ' \
              --preview='d={3}; [ -d "$d" ] && ls -- "$d" || echo "(running agent)"' \
              --preview-window=right:35%)

      [ -z "$choice" ] && exit 0

      entry_type=$(printf '%s' "$choice" | cut -f4)
      data=$(printf '%s' "$choice" | cut -f3)

      if [ "$entry_type" = "running" ]; then
        # Fork: spawn new agent in same directory as selected running agent
        sid="''${data#claude-agent-}"
        dir_file="${stateDir}/$sid.dir"
        spawn_dir="$HOME"
        [ -f "$dir_file" ] && spawn_dir=$(cat "$dir_file")
        claude-agent-spawn "$spawn_dir"
      else
        # Record to history and spawn
        { echo "$data"; cat "$history_file" 2>/dev/null || true; } \
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
          SessionStart        = [{ matcher = ""; hooks = [{ type = "command"; command = "${hookSessionStart}/bin/claude-agent-hook-session-start"; }]; }];
          UserPromptSubmit    = [{ matcher = ""; hooks = [{ type = "command"; command = "${hookUserPromptSubmit}/bin/claude-agent-hook-user-prompt-submit"; }]; }];
          Notification        = [{ matcher = ""; hooks = [{ type = "command"; command = "${hookNotification}/bin/claude-agent-hook-notification"; }]; }];
          PostToolUse         = [{ matcher = ""; hooks = [{ type = "command"; command = "${hookPostToolUse}/bin/claude-agent-hook-post-tool-use"; }]; }];
          PostToolUseFailure  = [{ matcher = ""; hooks = [{ type = "command"; command = "${hookPostToolUseFailure}/bin/claude-agent-hook-post-tool-use-failure"; }]; }];
          Stop                = [{ matcher = ""; hooks = [{ type = "command"; command = "${hookStop}/bin/claude-agent-hook-stop"; }]; }];
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
          "float, class:^claude-agents-picker$"
          "center, class:^claude-agents-picker$"
          "size 1200 550, class:^claude-agents-picker$"
          "workspace special:claude-agents, class:^claude-agents-picker$"
        ];
        bind = [
          "SUPER, D, togglespecialworkspace, claude-agents"
          "SUPER, O, exec, ${pkgs.kitty}/bin/kitty --class claude-agents-picker --override close_on_child_death=yes -e ${smartO}/bin/claude-agents-smart-o"
          "SUPER, P, exec, ${smartP}/bin/claude-agents-smart-p"
        ];
      };
    };
  };
}
