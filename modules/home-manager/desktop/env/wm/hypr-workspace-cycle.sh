#!/usr/bin/env bash
#===============================================================================
# Hyprland Isolated Workspace Ranges (with Per-Range Memory)
#===============================================================================
#
# Usage: hypr-workspace-cycle (next|prev|toggle|toggle-rotation|rotation-vertical|rotation-landscape)
#
#   next/prev           - Moves within current range; saves position to range-specific cache.
#   toggle              - Jumps between RANGES; restores last-used workspace. If
#                         ROTATE_WITH_TOGGLE_RANGE=1, also rotates to vertical when
#                         entering TOGGLE_RANGES (21–22) and to landscape when leaving.
#   toggle-rotation     - Toggle display rotation only (for corner gesture; no waydroid).
#   rotation-vertical   - Set display to vertical (for exec-once / scripts).
#   rotation-landscape  - Set display to landscape (for exec-once / scripts).
#
#-------------------------------------------------------------------------------
# CONFIGURATION
#-------------------------------------------------------------------------------
RANGES="1-12 21-22"
TOGGLE_RANGES="21-22"

# Rotation when entering/leaving TOGGLE_RANGES (e.g. vertical for 21–22, landscape otherwise)
# Set to 1 to enable; 0 to disable.
ROTATE_WITH_TOGGLE_RANGE="${ROTATE_WITH_TOGGLE_RANGE:-1}"
ROTATE_SCREEN="${ROTATE_SCREEN:-eDP-1}"
# Monitor keyword suffix (after "name,"): preferred,auto,<scale>,transform,<0|1>
ROTATE_LANDSCAPE_MONITOR="${ROTATE_LANDSCAPE_MONITOR:-preferred,auto,1.5,transform,0}"
ROTATE_VERTICAL_MONITOR="${ROTATE_VERTICAL_MONITOR:-preferred,auto,2,transform,1}"
ROTATE_LANDSCAPE_INPUT="${ROTATE_LANDSCAPE_INPUT:-0}"
ROTATE_VERTICAL_INPUT="${ROTATE_VERTICAL_INPUT:-1}"
#===============================================================================

set -euo pipefail

HYPRCTL="${HYPRCTL:-hyprctl}"
JQ="${JQ:-jq}"
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/hypr-workspace-memory"
mkdir -p "$CACHE_DIR"

# Apply landscape (horizontal) orientation
apply_landscape() {
  [[ "$ROTATE_WITH_TOGGLE_RANGE" != "1" ]] && return 0
  "$HYPRCTL" keyword monitor "${ROTATE_SCREEN},${ROTATE_LANDSCAPE_MONITOR}"
  "$HYPRCTL" keyword input:touchdevice:transform "$ROTATE_LANDSCAPE_INPUT"
  "$HYPRCTL" keyword input:tablet:transform "$ROTATE_LANDSCAPE_INPUT"
}

# Apply vertical orientation
apply_vertical() {
  [[ "$ROTATE_WITH_TOGGLE_RANGE" != "1" ]] && return 0
  "$HYPRCTL" keyword monitor "${ROTATE_SCREEN},${ROTATE_VERTICAL_MONITOR}"
  "$HYPRCTL" keyword input:touchdevice:transform "$ROTATE_VERTICAL_INPUT"
  "$HYPRCTL" keyword input:tablet:transform "$ROTATE_VERTICAL_INPUT"
}

# Toggle rotation (for corner gesture): if currently landscape → vertical, else → landscape
toggle_rotation() {
  local transform
  transform=$("$HYPRCTL" monitors -j | "$JQ" -r --arg n "$ROTATE_SCREEN" '.[] | select(.name == $n) | .transform')
  if [[ "${transform:-0}" == "0" ]]; then
    apply_vertical
  else
    apply_landscape
  fi
}

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

# Corner gesture: toggle rotation only (no workspace change)
if [[ "$DIRECTION" == "toggle-rotation" ]]; then
  toggle_rotation
  exit 0
fi
if [[ "$DIRECTION" == "rotation-vertical" ]]; then
  apply_vertical
  exit 0
fi
if [[ "$DIRECTION" == "rotation-landscape" ]]; then
  apply_landscape
  exit 0
fi

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

  # Optional: rotate display when entering/leaving toggle range (21–22 = vertical)
  if [[ "$ROTATE_WITH_TOGGLE_RANGE" == "1" ]]; then
    if [[ "$TARGET_RANGE" == "$SECOND_RANGE" ]]; then
      apply_vertical
    else
      apply_landscape
    fi
  fi

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
