# Open Graphide 2.0, the native Rust editor (monolith/gred-rs), on the
# monolith checkout. Bound to SUPER+SHIFT+Q in ./binds.nix.
#
# Runs a build already on this machine and never asks the Azure test worker
# for one: the worker sleeps after 30 idle minutes and waking it takes
# minutes, too long for a key. `gred-rs/scripts/try` is what fetches newer
# builds into ~/.cache/gred-rs/bin (named gred-<commit>); the newest of those
# runs here. Until one exists, gred-easy (the grim-easy branch build, the
# Orca window) runs with the Orca face asked for by name.
#
# The libraries gred loads come from gred-rs's dev environment, which
# scripts/try caches as ~/.cache/gred-rs/devenv-*.sh.
set -u

cache="${XDG_CACHE_HOME:-$HOME/.cache}/gred-rs"
project="${1:-$HOME/Documents/startup/Graphide/monolith}"

fail() {
	notify-send -a "Graphide 2.0" "Graphide 2.0 did not start" "$1" 2>/dev/null
	echo "graphide-editor: $1" >&2
	exit 1
}

bin=""
for b in $(ls -t "$cache"/bin/gred-* 2>/dev/null); do
	case "$(basename "$b")" in
	gred-[0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]*) bin="$b"; break ;;
	esac
done
if [ -z "$bin" ] && [ -x "$cache/bin/gred-easy" ]; then
	bin="$cache/bin/gred-easy"
	export GRED_LOOK="${GRED_LOOK:-orca}"
fi
[ -n "$bin" ] || fail "no build in $cache/bin: run gred-rs/scripts/try once to fetch one"

env="$(ls -t "$cache"/devenv-*.sh 2>/dev/null | head -n 1)"
[ -n "$env" ] || fail "no dev environment cached: run gred-rs/scripts/try once"

# shellcheck disable=SC1090
. "$env" 2>/dev/null
export GRED_LOG="${GRED_LOG:-gred=info,wgpu_hal=error,warn}"
cd "$project" || fail "no project at $project"
exec "$bin" "$project" >>"$cache/gred.log" 2>&1
