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
      sf="${stateDir}/$agent_sid.state"
      current=$(cat "$sf" 2>/dev/null || printf 'idle')
      # Only escalate to needs-approval if the agent is actually mid-task.
      # Notifications fired after Stop (e.g. recap summaries) arrive when the
      # state is already idle and must not pull the agent back out of idle.
      if [ "$current" = "working" ]; then
        printf 'needs-approval' > "$sf"
      fi
      notify-send "Claude Agent" "$msg" --icon=terminal &
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
    runtimeInputs = with pkgs; [ inotify-tools jq hyprland gawk coreutils kitty ];
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
        # Gaps: 24px between columns, 8px between stacked windows, 200px for stored windows
        local col_gap=24 win_gap=8 stored_h=200
        col_w=$(( (lw - 2*col_gap) / 3 ))

        local clients_json
        clients_json=$(hyprctl clients -j)

        local idle_pairs="" working_pairs="" approval_pairs="" stored_pairs=""
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
            stored)         stored_pairs+="$title"$'\t'"$addr"$'\n' ;;
          esac
          # Tint the kitty terminal background to reflect agent state
          local sock="${stateDir}/$sid.sock"
          if [ -S "$sock" ]; then
            case "$state" in
              idle)           kitty @ --to "unix:$sock" set-colors "background=#0d1f0d" >/dev/null 2>&1 || true ;;
              working)        kitty @ --to "unix:$sock" set-colors "background=#1f1a00" >/dev/null 2>&1 || true ;;
              needs-approval) kitty @ --to "unix:$sock" set-colors "background=#1f0d1f" >/dev/null 2>&1 || true ;;
              stored)         kitty @ --to "unix:$sock" set-colors "background=#0d0d1f" >/dev/null 2>&1 || true ;;
            esac
          fi
        done

        local idle_addrs=() working_addrs=() approval_addrs=() stored_addrs=()
        [ -n "$idle_pairs" ]     && readarray -t idle_addrs     < <(printf '%s' "$idle_pairs"     | sort -f | cut -f2)
        [ -n "$working_pairs" ]  && readarray -t working_addrs  < <(printf '%s' "$working_pairs"  | sort -f | cut -f2)
        [ -n "$approval_pairs" ] && readarray -t approval_addrs < <(printf '%s' "$approval_pairs" | sort -f | cut -f2)
        [ -n "$stored_pairs" ]   && readarray -t stored_addrs   < <(printf '%s' "$stored_pairs"   | sort -f | cut -f2)

        # layout_col <cx> <start_y> <avail_h> [addr ...]
        layout_col() {
          local cx="$1" start_y="$2" avail_h="$3"; shift 3
          local n="$#"
          [ "$n" -eq 0 ] && return 0
          local wh=$(( (avail_h - (n-1)*win_gap) / n ))
          local j=0 addr
          for addr in "$@"; do
            local wy=$(( start_y + j * (wh + win_gap) ))
            hyprctl dispatch movetoworkspacesilent "special:claude-agents,address:$addr" >/dev/null 2>&1 || true
            hyprctl dispatch movewindowpixel "exact $cx $wy,address:$addr" >/dev/null 2>&1 || true
            hyprctl dispatch resizewindowpixel "exact $col_w $wh,address:$addr" >/dev/null 2>&1 || true
            j=$(( j + 1 ))
          done
        }

        # layout_stored <cx> <start_y> [addr ...]
        layout_stored() {
          local cx="$1" start_y="$2"; shift 2
          local k=0 addr
          for addr in "$@"; do
            local wy=$(( start_y + k * (stored_h + win_gap) ))
            hyprctl dispatch movetoworkspacesilent "special:claude-agents,address:$addr" >/dev/null 2>&1 || true
            hyprctl dispatch movewindowpixel "exact $cx $wy,address:$addr" >/dev/null 2>&1 || true
            hyprctl dispatch resizewindowpixel "exact $col_w $stored_h,address:$addr" >/dev/null 2>&1 || true
            k=$(( k + 1 ))
          done
        }

        local n_idle="''${#idle_addrs[@]}" n_stored="''${#stored_addrs[@]}"
        local col1_x="$ox"

        # Column 1: idle windows (proportional, top) + stored windows (200px, bottom)
        if [ "$n_idle" -gt 0 ] && [ "$n_stored" -gt 0 ]; then
          local stored_total idle_avail
          stored_total=$(( n_stored * stored_h + (n_stored - 1) * win_gap ))
          idle_avail=$(( lh - stored_total - win_gap ))
          [ "$idle_avail" -lt 100 ] && idle_avail=100
          layout_col "$col1_x" "$oy" "$idle_avail" "''${idle_addrs[@]}"
          layout_stored "$col1_x" "$(( oy + idle_avail + win_gap ))" "''${stored_addrs[@]}"
        elif [ "$n_stored" -gt 0 ]; then
          layout_stored "$col1_x" "$oy" "''${stored_addrs[@]}"
        elif [ "$n_idle" -gt 0 ]; then
          layout_col "$col1_x" "$oy" "$lh" "''${idle_addrs[@]}"
        fi

        # Column 2: working
        [ "''${#working_addrs[@]}"  -gt 0 ] && layout_col "$(( ox + col_w + col_gap ))"     "$oy" "$lh" "''${working_addrs[@]}"  || true
        # Column 3: needs-approval
        [ "''${#approval_addrs[@]}" -gt 0 ] && layout_col "$(( ox + 2*(col_w + col_gap) ))" "$oy" "$lh" "''${approval_addrs[@]}" || true
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
        --override allow_remote_control=socket-only \
        --override "listen_on=unix:${stateDir}/$sid.sock" \
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
    runtimeInputs = [ pkgs.jq pkgs.hyprland pkgs.coreutils ];
    text = ''
      # Is any agent window currently fullscreened?
      fullscreened=$(hyprctl clients -j | jq -r '
        .[] | select(
          (.class | startswith("claude-agent-")) and
          ((.fullscreen // 0) != 0)
        ) | .address' | head -1)

      if [ -n "$fullscreened" ]; then
        # Un-fullscreen (batch: focus + toggle off in one IPC call to avoid races)
        hyprctl --batch "dispatch focuswindow address:$fullscreened ; dispatch fullscreen 0"
        for sf in "${stateDir}"/*.state; do
          [ -f "$sf" ] || continue
          printf '%s' "$(cat "$sf")" > "$sf"
          break
        done
      else
        # Ensure the overlay is visible on the focused monitor
        if ! hyprctl monitors -j | jq -e 'any(.[]; .focused == true and .specialWorkspace.name == "special:claude-agents")' >/dev/null 2>&1; then
          hyprctl dispatch togglespecialworkspace claude-agents
        fi
        # With follow_mouse=1 the active window is whatever is under the cursor.
        # Honour that if it's an agent; otherwise fall back to the first agent found.
        active_class=$(hyprctl activewindow -j | jq -r '.class // ""')
        if [[ "$active_class" == claude-agent-* ]]; then
          hyprctl dispatch fullscreen 0
        else
          agent_addr=$(hyprctl clients -j | jq -r '
            .[] | select(.class | startswith("claude-agent-")) | .address' | head -1)
          if [ -n "$agent_addr" ]; then
            hyprctl --batch "dispatch focuswindow address:$agent_addr ; dispatch fullscreen 0"
          fi
        fi
      fi
    '';
  };

  smartI = pkgs.writeShellApplication {
    name = "claude-agents-smart-i";
    runtimeInputs = [ pkgs.jq pkgs.hyprland pkgs.coreutils ];
    text = ''
      active_class=$(hyprctl activewindow -j | jq -r '.class // ""')
      if [[ "$active_class" == claude-agent-* ]]; then
        sid="''${active_class#claude-agent-}"
        sf="${stateDir}/$sid.state"
        if [ -f "$sf" ]; then
          state=$(cat "$sf")
          if [ "$state" = "stored" ]; then
            printf 'idle' > "$sf"
          else
            printf 'stored' > "$sf"
          fi
        fi
      fi
    '';
  };

  # ── Hover-to-expand daemon ────────────────────────────────────────────────────
  # Listens to Hyprland socket2 activewindowv2 events (follow_mouse=1 makes
  # these fire on hover). When an agent window is hovered it expands to 50% of
  # the column; others compress proportionally.
  #
  # Performance: AGENT_MAP caches the hyprctl clients -j output (one line per
  # agent: class\taddr\ttitle). It is refreshed only on openwindow/closewindow
  # events. addr_state and col_addrs use awk/bash reads on this string instead
  # of spawning jq per-event, eliminating the ~100ms compositor-blocking call
  # that caused the visible pause before animations started.

  hoverDaemon = pkgs.writeShellApplication {
    name = "claude-agents-hover";
    runtimeInputs = with pkgs; [ jq hyprland gawk coreutils inotify-tools socat ];
    text = ''
      log() { echo "[hover] $*" >&2; }

      stateDir="${stateDir}"
      PIPE=$(mktemp -u /tmp/claude-hover-XXXXXX)
      mkfifo "$PIPE"
      # Keep a R+W fd open so subshells can write via >&9 rather than >> "$PIPE".
      # O_RDWR on a FIFO doesn't block (Linux extension); writes to fd 9 land in
      # the same buffer that the main loop reads from fd 0.  This way the FIFO
      # path can be deleted without breaking debounce timer writes.
      exec 9<>"$PIPE"
      MAIN_PID=$BASHPID
      cleanup() {
        [ "$BASHPID" = "$MAIN_PID" ] || return 0
        kill "$(jobs -p)" 2>/dev/null || true
        rm -f "$PIPE"
      }
      trap cleanup EXIT INT TERM

      # Locate Hyprland event socket (Hyprland 0.41+ uses XDG_RUNTIME_DIR/hypr/)
      his_fallback=""
      for d in "$XDG_RUNTIME_DIR/hypr/"/*/; do
        if [ -d "$d" ]; then his_fallback=$(basename "$d"); break; fi
      done
      HIS="''${HYPRLAND_INSTANCE_SIGNATURE:-$his_fallback}"
      SOCK="$XDG_RUNTIME_DIR/hypr/$HIS/.socket2.sock"
      log "HIS=$HIS  SOCK=$SOCK  stateDir=$stateDir"

      if [ ! -S "$SOCK" ]; then
        log "ERROR: socket not found at $SOCK — cannot receive events"
      fi

      # Feed Hyprland events as "H:<event>" and state-file changes as "S"
      socat -u "UNIX-CONNECT:$SOCK" - 2>&1 \
        | while IFS= read -r ev; do printf 'H:%s\n' "$ev"; done >> "$PIPE" &
      inotifywait -m -q -e close_write,moved_to "$stateDir" --format 'S' >> "$PIPE" &
      log "event sources started"

      hovered_addr=""
      hovered_col="-1"
      pending_focus=""
      focus_pid=""
      reexpand_pid=""

      # AGENT_MAP: one line per agent window — "class\taddr\ttitle"
      # Refreshed by invalidate_agents (debounced); never on hover events.
      AGENT_MAP=""
      REFRESH_TIMER_PID=""

      refresh_agents() {
        AGENT_MAP=$(hyprctl clients -j | jq -r \
          '.[] | select(.class | startswith("claude-agent-")) | [.class, .address, .title] | join("\t")')
        log "agent map refreshed"
      }

      # Debounce agent-map invalidation — watcher repositions emit rapid
      # openwindow/closewindow events.  Collapse them into one refresh call.
      invalidate_agents() {
        [ -n "$REFRESH_TIMER_PID" ] && kill "$REFRESH_TIMER_PID" 2>/dev/null || true
        ( trap - EXIT INT TERM; sleep 0.4; printf 'REFRESH\n' >&9 ) &
        REFRESH_TIMER_PID=$!
      }

      # Cache monitor geometry — avoids a hyprctl round-trip per expand/restore
      G_OX=0 G_OY=0 G_LH=0 G_CW=0
      init_params() {
        local mon mw mh scale rr rb lw
        mon=$(hyprctl monitors -j | jq 'map(select(.focused))[0] // .[0]')
        G_OX=$(printf '%s' "$mon" | jq '.reserved[0]')
        G_OY=$(printf '%s' "$mon" | jq '.reserved[1]')
        mw=$(printf '%s' "$mon" | jq '.width')
        mh=$(printf '%s' "$mon" | jq '.height')
        scale=$(printf '%s' "$mon" | jq '.scale')
        rr=$(printf '%s' "$mon" | jq '.reserved[2]')
        rb=$(printf '%s' "$mon" | jq '.reserved[3]')
        lw=$(awk "BEGIN{printf \"%d\", $mw/$scale - $G_OX - $rr}")
        G_LH=$(awk "BEGIN{printf \"%d\", $mh/$scale - $G_OY - $rb}")
        G_CW=$(( (lw - 2*24) / 3 ))
      }

      col_cx() {
        case "$1" in
          0) printf '%d' "$G_OX" ;;
          1) printf '%d' "$(( G_OX + G_CW + 24 ))" ;;
          2) printf '%d' "$(( G_OX + 2*(G_CW + 24) ))" ;;
        esac
      }

      addr_state() {
        local addr="$1" class sid sf
        class=$(printf '%s\n' "$AGENT_MAP" | awk -F'\t' -v a="$addr" '$2 == a {print $1; exit}')
        [[ "$class" == claude-agent-* ]] || return 0
        sid="''${class#claude-agent-}"
        sf="$stateDir/$sid.state"
        [ -f "$sf" ] && cat "$sf" || true
      }

      state_col() {
        case "$1" in
          idle|stored)    printf '0' ;;
          working)        printf '1' ;;
          needs-approval) printf '2' ;;
          *)              printf '-1' ;;
        esac
      }

      # col_addrs <col> [state_filter]
      col_addrs() {
        local col="$1" filter="''${2:-}" class addr title sid sf state
        [ -z "$AGENT_MAP" ] && return 0
        while IFS=$'\t' read -r class addr title; do
          [[ "$class" == claude-agent-* ]] || continue
          sid="''${class#claude-agent-}"
          sf="$stateDir/$sid.state"
          [ -f "$sf" ] || continue
          state=$(cat "$sf")
          [ "$(state_col "$state")" = "$col" ] || continue
          [ -n "$filter" ] && [ "$state" != "$filter" ] && continue
          printf '%s\t%s\n' "$title" "$addr"
        done < <(printf '%s\n' "$AGENT_MAP") | sort -f | cut -f2
      }

      do_expand() {
        local target="$1" state col cx
        state=$(addr_state "$target")
        [ -z "$state" ] && { log "expand: no state for $target, skipping"; return 0; }
        col=$(state_col "$state")
        [ "$col" = "-1" ] && { log "expand: unknown col for state '$state'"; return 0; }

        cx=$(col_cx "$col")

        # Col 0: only expand idle windows; compute height excluding pinned stored area
        local addrs=() avail_h="$G_LH"
        if [ "$col" = "0" ]; then
          readarray -t addrs < <(col_addrs "$col" "idle")
          local n_stored=0 sf_s
          for sf_s in "$stateDir"/*.state; do
            [ -f "$sf_s" ] || continue
            [ "$(cat "$sf_s")" = "stored" ] && n_stored=$(( n_stored + 1 ))
          done
          [ "$n_stored" -gt 0 ] && avail_h=$(( G_LH - n_stored * 200 - n_stored * 8 ))
          [ "$avail_h" -lt 100 ] && avail_h=100
        else
          readarray -t addrs < <(col_addrs "$col")
        fi
        local n="''${#addrs[@]}"
        [ "$n" -lt 2 ] && { log "expand: only $n window(s) in col $col, nothing to compress"; return 0; }

        local half other_h
        half=$(( avail_h / 2 ))
        log "expand: target=$target col=$col n=$n half=$half avail=$avail_h"
        other_h=$(( (avail_h - half - (n-1)*8) / (n-1) ))
        [ "$other_h" -lt 40 ] && { log "expand: other_h=$other_h too small, skipping"; return 0; }

        local y="$G_OY" addr wh batch=""
        for addr in "''${addrs[@]}"; do
          if [ "$addr" = "$target" ]; then wh="$half"; else wh="$other_h"; fi
          batch+="dispatch movewindowpixel exact $cx $y,address:$addr ; "
          batch+="dispatch resizewindowpixel exact $G_CW $wh,address:$addr ; "
          y=$(( y + wh + 8 ))
        done
        hyprctl --batch "''${batch% ; }" >/dev/null 2>&1 || true

        hovered_addr="$target"
        hovered_col="$col"
      }

      do_restore() {
        local col="$1" cx batch=""
        [ "$col" = "-1" ] && return 0
        cx=$(col_cx "$col")

        if [ "$col" = "0" ]; then
          local idle_pairs="" stored_pairs="" class addr title sid sf state
          while IFS=$'\t' read -r class addr title; do
            [[ "$class" == claude-agent-* ]] || continue
            sid="''${class#claude-agent-}"
            sf="$stateDir/$sid.state"
            [ -f "$sf" ] || continue
            state=$(cat "$sf")
            [ "$(state_col "$state")" = "0" ] || continue
            case "$state" in
              idle)   idle_pairs+="$title"$'\t'"$addr"$'\n' ;;
              stored) stored_pairs+="$title"$'\t'"$addr"$'\n' ;;
            esac
          done < <(printf '%s\n' "$AGENT_MAP")

          local idle_addrs=() stored_addrs=()
          [ -n "$idle_pairs" ]   && readarray -t idle_addrs   < <(printf '%s' "$idle_pairs"   | sort -f | cut -f2)
          [ -n "$stored_pairs" ] && readarray -t stored_addrs < <(printf '%s' "$stored_pairs" | sort -f | cut -f2)

          local n_idle="''${#idle_addrs[@]}" n_stored="''${#stored_addrs[@]}" y="$G_OY"
          local stored_total idle_avail idle_wh

          if [ "$n_idle" -gt 0 ] && [ "$n_stored" -gt 0 ]; then
            stored_total=$(( n_stored * 200 + (n_stored-1) * 8 ))
            idle_avail=$(( G_LH - stored_total - 8 ))
            [ "$idle_avail" -lt 100 ] && idle_avail=100
            idle_wh=$(( (idle_avail - (n_idle-1)*8) / n_idle ))
            for addr in "''${idle_addrs[@]}"; do
              batch+="dispatch movewindowpixel exact $cx $y,address:$addr ; "
              batch+="dispatch resizewindowpixel exact $G_CW $idle_wh,address:$addr ; "
              y=$(( y + idle_wh + 8 ))
            done
            y=$(( G_OY + idle_avail + 8 ))
            for addr in "''${stored_addrs[@]}"; do
              batch+="dispatch movewindowpixel exact $cx $y,address:$addr ; "
              batch+="dispatch resizewindowpixel exact $G_CW 200,address:$addr ; "
              y=$(( y + 200 + 8 ))
            done
          elif [ "$n_stored" -gt 0 ]; then
            for addr in "''${stored_addrs[@]}"; do
              batch+="dispatch movewindowpixel exact $cx $y,address:$addr ; "
              batch+="dispatch resizewindowpixel exact $G_CW 200,address:$addr ; "
              y=$(( y + 200 + 8 ))
            done
          elif [ "$n_idle" -gt 0 ]; then
            idle_wh=$(( (G_LH - (n_idle-1)*8) / n_idle ))
            for addr in "''${idle_addrs[@]}"; do
              batch+="dispatch movewindowpixel exact $cx $y,address:$addr ; "
              batch+="dispatch resizewindowpixel exact $G_CW $idle_wh,address:$addr ; "
              y=$(( y + idle_wh + 8 ))
            done
          fi
        else
          local addrs=()
          readarray -t addrs < <(col_addrs "$col")
          local n="''${#addrs[@]}"
          [ "$n" -eq 0 ] && return 0
          local wh=$(( (G_LH - (n-1)*8) / n ))
          local y="$G_OY" addr
          for addr in "''${addrs[@]}"; do
            batch+="dispatch movewindowpixel exact $cx $y,address:$addr ; "
            batch+="dispatch resizewindowpixel exact $G_CW $wh,address:$addr ; "
            y=$(( y + wh + 8 ))
          done
        fi
        batch="''${batch% ; }"
        [ -n "$batch" ] && hyprctl --batch "$batch" >/dev/null 2>&1 || true
      }

      on_focus() {
        local new_addr="$1" new_state new_col
        new_state=$(addr_state "$new_addr")
        new_col="-1"
        [ -n "$new_state" ] && new_col=$(state_col "$new_state")
        log "focus addr=$new_addr state='$new_state' col=$new_col hovered_col=$hovered_col"

        [ "$new_addr" = "$hovered_addr" ] && return 0

        if [ "$hovered_col" != "-1" ] && [ "$new_col" != "$hovered_col" ]; then
          local old_col="$hovered_col"
          hovered_addr=""
          hovered_col="-1"
          log "restoring col $old_col"
          do_restore "$old_col"
        fi

        # Stored windows stay small intentionally — never expand them
        [ "$new_col" != "-1" ] && [ "$new_state" != "stored" ] && do_expand "$new_addr" || true
      }

      # Pre-compute monitor geometry, build initial agent map, expand whatever
      # is already focused at startup
      init_params
      refresh_agents
      initial=$(hyprctl activewindow -j | jq -r '.address // ""')
      [ -n "$initial" ] && on_focus "$initial" || true

      # shellcheck disable=SC2094
      while IFS= read -r line; do
        case "''${line%%>>*}" in
          H:activewindowv2)
            # Debounce: O(1) here — update pending addr and reset a 20ms timer.
            # on_focus only runs once the cursor has settled.
            addr="0x''${line#H:activewindowv2>>}"
            pending_focus="$addr"
            [ -n "$focus_pid" ] && kill "$focus_pid" 2>/dev/null || true
            ( trap - EXIT INT TERM; sleep 0.02; printf 'FOCUS:%s\n' "$addr" >&9 ) &
            focus_pid=$!
            ;;
          FOCUS:*)
            addr="''${line#FOCUS:}"
            focus_pid=""
            [ "$addr" = "$pending_focus" ] && on_focus "$addr" || true
            ;;
          H:openwindow|H:closewindow)
            invalidate_agents
            ;;
          REFRESH*)
            REFRESH_TIMER_PID=""
            refresh_agents
            ;;
          S)
            # Watcher repositioned; reexpand the hovered window after it settles
            [ -n "$reexpand_pid" ] && kill "$reexpand_pid" 2>/dev/null || true
            ha="$hovered_addr"
            ( trap - EXIT INT TERM
              sleep 0.25
              if [ -n "$ha" ]; then
                active=$(hyprctl activewindow -j | jq -r '.address // ""')
                [ "$active" = "$ha" ] && do_expand "$ha" || true
              fi
            ) &
            reexpand_pid="$!"
            ;;
        esac
      done < "$PIPE"
    '';
  };

in {
  options.programs.claudeAgents.enable =
    mkEnableOption "Claude Code agent management with Hyprland workspace integration";

  config = mkIf cfg.enable {
    home.packages = [ watcher spawner smartO smartP smartI hoverDaemon ];

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

    systemd.user.services.claude-agents-hover = {
      Unit = {
        Description = "Claude Code agent hover-to-expand";
        After = [ "graphical-session.target" ];
        PartOf = [ "graphical-session.target" ];
      };
      Service = {
        Type = "simple";
        ExecStart = "${hoverDaemon}/bin/claude-agents-hover";
        Restart = "on-failure";
        RestartSec = "2s";
        # socat needs to locate the Hyprland socket
        PassEnvironment = [ "HYPRLAND_INSTANCE_SIGNATURE" ];
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
          "SUPER, I, exec, ${smartI}/bin/claude-agents-smart-i"
        ];
      };
    };
  };
}
