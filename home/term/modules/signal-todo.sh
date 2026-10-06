# Send docs/TODO.md to the Signal chat with Ben, at most once a day.
#
#   signal-todo          send now (manual trigger; also arms the daily timer)
#   signal-todo --auto   timer mode: send only if armed, not yet sent today,
#                        it is past SIGNAL_TODO_NOT_BEFORE (hour, default 8),
#                        and Signal Desktop is running
#
# Config: ~/.config/signal-todo/env  (ACCOUNT=+1..., and GROUP_ID=... or RECIPIENT=+1...)
# State:  ~/.local/state/signal-todo/last-sent  (date of the last send; absent = not armed)

CONF="$HOME/.config/signal-todo/env"
STATE_DIR="$HOME/.local/state/signal-todo"
STAMP="$STATE_DIR/last-sent"
TODO="${SIGNAL_TODO_FILE:?}"
SECTIONS="${SIGNAL_TODO_SECTIONS:?}"   # "|"-separated "## " headings to send
TODAY="$(date +%F)"

mkdir -p "$STATE_DIR"
exec 9>"$STATE_DIR/lock"
flock -n 9 || exit 0   # another run is mid-send

if [[ "${1:-}" == "--auto" ]]; then
	[[ -f "$STAMP" ]] || { echo "not armed yet: run signal-todo by hand once"; exit 0; }
	[[ "$(cat "$STAMP")" == "$TODAY" ]] && exit 0
	# Not before the morning: a late night past midnight would otherwise send
	# the new day's reminder at 1 a.m. A manual run ignores this.
	(( 10#$(date +%H) >= ${SIGNAL_TODO_NOT_BEFORE:-8} )) || exit 0
	pgrep -f 'signal-desktop.*app\.asar' >/dev/null || exit 0
fi

[[ -f "$CONF" ]] || { echo "missing $CONF" >&2; exit 1; }
# shellcheck source=/dev/null
source "$CONF"
: "${ACCOUNT:?set ACCOUNT in $CONF}"
if [[ -n "${GROUP_ID:-}" ]]; then target=(-g "$GROUP_ID")
elif [[ -n "${RECIPIENT:-}" ]]; then target=("$RECIPIENT")
else echo "set GROUP_ID or RECIPIENT in $CONF" >&2; exit 1
fi

# Keep the linked device in sync; Signal unlinks devices that never check in.
signal-cli -a "$ACCOUNT" receive -t 5 >/dev/null 2>&1 || true

# Only the listed "## " sections, headings included; everything else is dropped.
body="$(awk -v want="$SECTIONS" '
	BEGIN { n = split(want, w, "|"); for (i = 1; i <= n; i++) keep[w[i]] = 1 }
	/^## / { on = (substr($0, 4) in keep) }
	/^#/ && !/^## / && !/^###/ { on = 0 }
	on
' "$TODO")"
[[ -n "$body" ]] || { echo "no sections matching $SECTIONS in $TODO" >&2; exit 1; }
msg="TODO for $(date '+%a %b %-d')"$'\n\n'"$body"
signal-cli -a "$ACCOUNT" send -m "$msg" "${target[@]}"
echo "$TODAY" >"$STAMP"
echo "sent"
