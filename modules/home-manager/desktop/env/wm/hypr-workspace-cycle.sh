#!/usr/bin/env bash
#===============================================================================
# Hyprland Isolated Workspace Ranges (with Per-Range Memory)
#===============================================================================
#
# Usage: hypr-workspace-cycle (next|prev|toggle)
#
#   next/prev - Moves within current range; saves position to range-specific cache.
#   toggle    - Jumps between RANGES; always restores the last-used workspace 
#               for the target range.
#
#-------------------------------------------------------------------------------
# CONFIGURATION
#-------------------------------------------------------------------------------
RANGES="1-12 21-22"
TOGGLE_RANGES="21-22"
#===============================================================================

set -euo pipefail

HYPRCTL="${HYPRCTL:-hyprctl}"
JQ="${JQ:-jq}"
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/hypr-workspace-memory"
mkdir -p "$CACHE_DIR"

# Find which range contains the given workspace number
find_range_for_workspace() {
  local ws="$1"
  for range in $RANGES; do
    local start="${range%-*}"
    local end="${range#*-}"
    if (( ws >= start && ws <= end )); then
      echo "$range"
      return
    fi
  done
  echo ""
}

# Get the last used workspace for a specific range string (e.g., "1-12")
get_range_last_ws() {
  local range_str="$1"
  local cache_file="$CACHE_DIR/range_${range_str}"
  if [[ -f "$cache_file" ]]; then
    cat "$cache_file"
  else
    echo "${range_str%-*}" # Default to start of range
  fi
}

# Save the current workspace as the "last used" for its range
save_range_last_ws() {
  local ws="$1"
  local range_str
  range_str=$(find_range_for_workspace "$ws")
  if [[ -n "$range_str" ]]; then
    echo "$ws" > "$CACHE_DIR/range_${range_str}"
  fi
}

# Main Logic
DIRECTION="${1:-next}"
CURRENT_RAW=$("$HYPRCTL" activeworkspace -j | "$JQ" -r .name)

# Sanitize workspace name
CURRENT_NUM=1
[[ "$CURRENT_RAW" =~ ^[0-9]+$ ]] && CURRENT_NUM=$((10#$CURRENT_RAW))

# Always update memory for the current range before moving
save_range_last_ws "$CURRENT_NUM"

#--- TOGGLE LOGIC (Range Jumping) ---
if [[ "$DIRECTION" == "toggle" ]]; then
  # Determine which range we are jumping TO
  # If we are in 21-22, we jump to 1-12. If in 1-12, we jump to 21-22.
  FIRST_RANGE="${RANGES%% *}"
  SECOND_RANGE="${RANGES##* }"
  
  CURRENT_RANGE=$(find_range_for_workspace "$CURRENT_NUM")
  
  if [[ "$CURRENT_RANGE" == "$SECOND_RANGE" ]]; then
    TARGET_RANGE="$FIRST_RANGE"
  else
    TARGET_RANGE="$SECOND_RANGE"
  fi

  TARGET=$(get_range_last_ws "$TARGET_RANGE")
  "$HYPRCTL" dispatch workspace "$TARGET"
  exit 0
fi

#--- NEXT/PREV LOGIC (Within Range) ---
RANGE=$(find_range_for_workspace "$CURRENT_NUM")
[[ -z "$RANGE" ]] && RANGE="${RANGES%% *}"

START="${RANGE%-*}"
END="${RANGE#*-}"

case "$DIRECTION" in
  next)
    (( CURRENT_NUM < END )) && TARGET=$(( CURRENT_NUM + 1 )) || TARGET=$CURRENT_NUM
    ;;
  prev)
    (( CURRENT_NUM > START )) && TARGET=$(( CURRENT_NUM - 1 )) || TARGET=$CURRENT_NUM
    ;;
  *) exit 1 ;;
esac

# Update memory for the NEW workspace in this range
save_range_last_ws "$TARGET"
"$HYPRCTL" dispatch workspace "$TARGET"
