# Open Graphide on the monolith checkout with gdev's master instance, after
# bringing that instance up to the newest published master build. Bound to
# SUPER+SHIFT+Q in ./binds.nix.
#
# The services.graphide-master-build timer (hosts/XiaNix/home.nix) publishes
# every master that can change the app on XiaServer and normally installs it
# here as it goes, so the update below is usually a no-op. It is still done
# here because the timer can be behind, stopped, or have failed an install.
#
# `gdev run master` would update too, but it does nothing while the master
# instance is running, so this asks XiaServer which build is newest itself
# (the same ssh call gdev makes, from the same hosts) and installs that one
# with `gdev run master@<sha> --no-open`, as master-build does.
#
# After the window is up, a toast says so if the build it runs is behind
# origin/master, and why.
set -u

export PATH="$HOME/.local/bin:$PATH"
project="${1:-$HOME/Documents/startup/Graphide/monolith}"

# The monolith checkout's own copy does this job when it is there, so it
# changes without a nixswitch: it swaps an open window to a newer build with
# its terminals kept, and waits for a build in flight. What follows is the
# fallback for a machine without it.
key="$HOME/Documents/startup/Graphide/monolith/gred-rs/scripts/master-key"
if [ -x "$key" ]; then
	exec "$key" "$project"
fi
log="${XDG_STATE_HOME:-$HOME/.local/state}/graphide-master-key.log"
mkdir -p "$(dirname "$log")"

toast() {
	notify-send -a "Graphide" "$@" 2>/dev/null
}

installed() {
	gdev which master --json 2>/dev/null | jq -r '.build.commit // empty' || true
}

# Prints the newest published commit on its first line and the publisher's
# last attempt (attempt.json) on its second, or nothing when XiaServer is out
# of reach.
published() {
	local hosts host
	hosts="$(printf '%s' "${GDEV_MASTER_HOSTS:-10.0.0.100 100.96.50.71 xiaserver.tail028f45.ts.net}" | tr ',' ' ')"
	# shellcheck disable=SC2086 # one host per word
	for host in $hosts; do
		if ssh -o BatchMode=yes -o ConnectTimeout=5 "${GDEV_MASTER_USER:-graphide-build}@$host" \
			"d=${GDEV_MASTER_DIR:-/srv/build/graphide-master}; cat \"\$d/latest\"; echo; tr -d '\n' <\"\$d/attempt.json\" 2>/dev/null; echo" 2>/dev/null; then
			return 0
		fi
	done
	return 1
}

command -v gdev >/dev/null || { toast "Graphide did not start" "gdev is not installed (~/.local/bin/gdev)"; exit 1; }

reason=""
current="$(installed)"
if listing="$(published)"; then
	latest="$(printf '%s\n' "$listing" | sed -n 1p | tr -d '[:space:]')"
	attempt="$(printf '%s\n' "$listing" | sed -n 2p)"
	if [ -n "$latest" ] && [ "$latest" != "$current" ]; then
		toast "Updating Graphide" "master ${current:0:10} -> ${latest:0:10}"
		if timeout 600 gdev run "master@$latest" --no-open --quiet >>"$log" 2>&1; then
			current="$(installed)"
		else
			reason="updating to ${latest:0:10} failed: $(tail -n 1 "$log")"
		fi
	fi
	if [ -z "$reason" ] && [ -n "$attempt" ]; then
		a_commit="$(printf '%s' "$attempt" | jq -r '.commit // empty' 2>/dev/null)"
		a_result="$(printf '%s' "$attempt" | jq -r '.result // empty' 2>/dev/null)"
		if [ "$a_result" = failed ] && [ "$a_commit" != "$latest" ]; then
			reason="the publisher's last build, ${a_commit:0:10}, failed"
		fi
	fi
else
	reason="XiaServer is out of reach, so no newer build could be fetched"
fi

[ -n "$current" ] || { toast "Graphide did not start" "no master build installed; ${reason:-run gdev run master once}"; exit 1; }

echo "--- $(date -Is) opening master ${current:0:10} on $project" >>"$log"
setsid -f gdev exec master -- graphide "$project" >>"$log" 2>&1 </dev/null

# Behind origin/master? Counted against a fresh fetch of the checkout.
timeout 30 git -C "$project" fetch --quiet origin master 2>/dev/null ||
	reason="${reason:+$reason; }origin/master could not be fetched, counted against the last fetch"
behind="$(git -C "$project" rev-list --count "$current..origin/master" 2>/dev/null)" || {
	toast -u critical "Graphide may be behind master" "${current:0:10} is not in $project${reason:+; $reason}"
	exit 0
}
if [ "$behind" -gt 0 ]; then
	if [ -z "$reason" ]; then
		if systemctl --user -q is-active graphide-master-build.service; then
			reason="a newer master is being built now"
		else
			reason="the newer commits are not built (master-build skips commits that cannot change the app)"
		fi
	fi
	toast -u critical "Graphide is $behind commit(s) behind master" "running ${current:0:10}: $reason"
fi
