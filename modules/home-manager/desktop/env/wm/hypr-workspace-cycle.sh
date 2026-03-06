#!/usr/bin/env bash
#===============================================================================
# Hyprland Isolated Workspace Ranges
#===============================================================================
#
# Each range cycles only within itself. Swiping/scroll never crosses range
# boundaries. You can only enter an isolated range via an explicit keybind
# (e.g. Super+X) or gesture (e.g. 4-finger hold).
#
# Usage: hypr-workspace-cycle (next|prev|toggle)
#
#   next   - Cycle to next workspace within current range
#   prev   - Cycle to previous workspace within current range
#   toggle - If in a TOGGLE_RANGES workspace, save current and go back; else
#            jump to last-used workspace in toggle range (or first if none saved)
#
#-------------------------------------------------------------------------------
# CONFIGURATION - Edit these to add or modify isolated ranges
#-------------------------------------------------------------------------------
#
# RANGES: Space-separated list of "start-end" (inclusive) workspace ranges.
#         Order matters: first matching range wins.
#
#   Format:  "start-end"  e.g. "1-12" = workspaces 1 through 12
#
#   Examples:
#     RANGES="1-12 21-22"           # Main (1-12) + magic (21-22)
#     RANGES="1-10 11-12 21-22"     # Split main into two ranges
#     RANGES="1-12 21-22 31-32"     # Add a third isolated range (e.g. notetaking)
#
RANGES="1-12 21-22"
#
#-------------------------------------------------------------------------------
# TOGGLE RANGES (optional) - Ranges that have a "toggle" entry point
#-------------------------------------------------------------------------------
#
# Workspaces in these ranges are only reachable via toggle (e.g. Super+X or
# 4-finger hold). When you toggle, you jump to the first workspace of the
# range. Toggle again to go back to where you were.
#
# Format: Same as RANGES. Used by hypr-workspace-toggle (separate script).
#
TOGGLE_RANGES="21-22"
#
#===============================================================================

set -euo pipefail

HYPRCTL="${HYPRCTL:-hyprctl}"
JQ="${JQ:-jq}"

#-------------------------------------------------------------------------------
# Parse a "start-end" range into a list of workspace numbers
# Usage: parse_range "1-12"
# Output: "1 2 3 4 5 6 7 8 9 10 11 12"
#-------------------------------------------------------------------------------
parse_range() {
  local range="$1"
  local start end i
  start="${range%-*}"
  end="${range#*-}"
  for (( i=start; i<=end; i++ )); do
    echo -n "$i "
  done
}

#-------------------------------------------------------------------------------
# Build a list of all workspaces in all ranges (order preserved)
# Usage: all_workspaces_in_range "1-12"
#-------------------------------------------------------------------------------
range_to_list() {
  parse_range "$1"
}

#-------------------------------------------------------------------------------
# Find which range contains the given workspace number
# Returns the range string (e.g. "1-12") or empty if not in any range
#-------------------------------------------------------------------------------
find_range_for_workspace() {
  local ws="$1"
  local range start end
  for range in $RANGES; do
    start="${range%-*}"
    end="${range#*-}"
    if (( ws >= start && ws <= end )); then
      echo "$range"
      return
    fi
  done
  echo ""
}

#-------------------------------------------------------------------------------
# Get the next workspace in the same range (wrap around)
#-------------------------------------------------------------------------------
cycle_next_in_range() {
  local range="$1"
  local current="$2"
  local start end count idx next
  start="${range%-*}"
  end="${range#*-}"
  count=$(( end - start + 1 ))
  idx=$(( (current - start + 1) % count ))
  next=$(( start + idx ))
  echo $next
}

#-------------------------------------------------------------------------------
# Get the previous workspace in the same range (wrap around)
#-------------------------------------------------------------------------------
cycle_prev_in_range() {
  local range="$1"
  local current="$2"
  local start end count idx prev
  start="${range%-*}"
  end="${range#*-}"
  count=$(( end - start + 1 ))
  idx=$(( (current - start - 1 + count) % count ))
  prev=$(( start + idx ))
  echo $prev
}

#-------------------------------------------------------------------------------
# Check if workspace number is in any TOGGLE_RANGES
#-------------------------------------------------------------------------------
is_in_toggle_ranges() {
  local ws="$1"
  local range start end
  for range in $TOGGLE_RANGES; do
    start="${range%-*}"
    end="${range#*-}"
    if (( ws >= start && ws <= end )); then
      return 0
    fi
  done
  return 1
}

#-------------------------------------------------------------------------------
# Get first workspace of first TOGGLE_RANGES range (entry point for toggle)
#-------------------------------------------------------------------------------
first_toggle_workspace() {
  local range="${TOGGLE_RANGES%% *}"
  echo "${range%-*}"
}

#-------------------------------------------------------------------------------
# State file for "last workspace in toggle range" (for toggle-back behavior)
#-------------------------------------------------------------------------------
LAST_TOGGLE_FILE="${XDG_CACHE_HOME:-$HOME/.cache}/hypr-workspace-cycle-last-toggle"

save_last_toggle_workspace() {
  local ws="$1"
  mkdir -p "$(dirname "$LAST_TOGGLE_FILE")"
  echo "$ws" > "$LAST_TOGGLE_FILE"
}

get_last_toggle_workspace() {
  if [[ -f "$LAST_TOGGLE_FILE" ]]; then
    local saved
    saved=$(cat "$LAST_TOGGLE_FILE" 2>/dev/null)
    if [[ -n "$saved" && "$saved" =~ ^[0-9]+$ ]] && is_in_toggle_ranges "$saved"; then
      echo "$saved"
      return
    fi
  fi
  echo ""
}

#-------------------------------------------------------------------------------
# Main
#-------------------------------------------------------------------------------
DIRECTION="${1:-next}"
CURRENT_RAW=$("$HYPRCTL" activeworkspace -j | "$JQ" -r .name)

# If workspace name is not numeric (e.g. "special:magic"), treat as workspace 1
# for cycling purposes (so we cycle within the first range)
CURRENT_NUM=1
if [[ "$CURRENT_RAW" =~ ^[0-9]+$ ]]; then
  CURRENT_NUM=$((10#$CURRENT_RAW))
fi

# Handle toggle: if in a toggle range, save and go back; else jump to last-used
# workspace in toggle range (or first if none saved)
if [[ "$DIRECTION" == "toggle" ]]; then
  if is_in_toggle_ranges "$CURRENT_NUM"; then
    save_last_toggle_workspace "$CURRENT_NUM"
    "$HYPRCTL" dispatch workspace previous
  else
    TARGET=$(get_last_toggle_workspace)
    [[ -z "$TARGET" ]] && TARGET=$(first_toggle_workspace)
    "$HYPRCTL" dispatch workspace "$TARGET"
  fi
  exit 0
fi

RANGE=$(find_range_for_workspace "$CURRENT_NUM")

# If not in any configured range, use first range
if [[ -z "$RANGE" ]]; then
  RANGE="${RANGES%% *}"
  CURRENT_NUM="${RANGE%-*}"
fi

case "$DIRECTION" in
  next)
    TARGET=$(cycle_next_in_range "$RANGE" "$CURRENT_NUM")
    ;;
  prev)
    TARGET=$(cycle_prev_in_range "$RANGE" "$CURRENT_NUM")
    ;;
  *)
    echo "Usage: $0 (next|prev|toggle)" >&2
    exit 1
    ;;
esac

"$HYPRCTL" dispatch workspace "$TARGET"
