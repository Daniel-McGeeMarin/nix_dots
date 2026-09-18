#!/usr/bin/env bash
set -euo pipefail

# The command intentionally renders timestamps in local time; pin it here so
# the transcript contract is deterministic on every developer machine and CI.
export TZ=UTC

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

sqlite3_bin="${SQLITE3_BIN:-sqlite3}"
db="$tmp_dir/signal.sqlite"

"$sqlite3_bin" "$db" <<'SQL'
CREATE TABLE conversations (
  id TEXT PRIMARY KEY,
  type TEXT,
  name TEXT,
  profileName TEXT,
  profileFamilyName TEXT,
  profileFullName TEXT,
  e164 TEXT,
  serviceId TEXT
);
CREATE TABLE messages (
  conversationId TEXT,
  type TEXT,
  body TEXT,
  sourceServiceId TEXT,
  source TEXT,
  timestamp INTEGER,
  sent_at INTEGER,
  received_at_ms INTEGER,
  isErased INTEGER
);

INSERT INTO conversations VALUES
  ('chat-work', 'group', 'Graphide Work', NULL, NULL, NULL, NULL, NULL),
  ('chat-personal', 'private', NULL, 'Mom', NULL, 'Mom', '+15550000000', 'ACI:mom'),
  ('person-alice', 'private', NULL, 'Alice', 'Builder', 'Alice Builder', '+15551111111', 'ACI:alice'),
  ('person-bob', 'private', NULL, 'Bob', 'Writer', 'Bob Writer', '+15552222222', 'ACI:bob');

INSERT INTO messages VALUES
  ('chat-work', 'incoming', 'Graphide alpha decision', 'ACI:alice', '+15551111111', 1000, 1000, 1000, 0),
  ('chat-work', 'incoming', 'Bob side note', 'ACI:bob', '+15552222222', 2000, 2000, 2000, 0),
  ('chat-work', 'outgoing', 'My reply', NULL, NULL, 3000, 3000, 3000, 0),
  ('chat-work', 'incoming', 'Graphide deadline Friday', 'ACI:alice', '+15551111111', 4000, 4000, 4000, 0),
  ('chat-work', 'incoming', '', 'ACI:alice', '+15551111111', 5000, 5000, 5000, 0),
  ('chat-personal', 'incoming', 'Dinner at seven', 'ACI:mom', '+15550000000', 6000, 6000, 6000, 0);
SQL

cat > "$tmp_dir/fzf" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
input="$(cat)"
case "$*" in
  *"Signal chat> "*) grep $'^[^\t]*\tGraphide Work\t' <<< "$input" ;;
  *"Sender> "*)
    case "${SIGNAL_REDACT_TEST_SENDER:-alice}" in
      all) grep $'^all\tBoth\t' <<< "$input" ;;
      me) grep $'^outgoing:me\tMe\t' <<< "$input" ;;
      *) grep $'^incoming:ACI:alice\tAlice Builder\t' <<< "$input" ;;
    esac
    ;;
  *) echo "unexpected fzf prompt: $*" >&2; exit 1 ;;
esac
MOCK

cat > "$tmp_dir/privatellm-redact" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
tee "$SIGNAL_REDACT_TEST_CAPTURE"
MOCK

chmod +x "$tmp_dir/fzf" "$tmp_dir/privatellm-redact"

export PATH="$tmp_dir:$PATH"
export SIGNAL_DB="$db"
export SIGNAL_PLAINTEXT_DB=1
export SIGNAL_SQLITE_BIN="$sqlite3_bin"
export SIGNAL_REDACT_TEST_CAPTURE="$tmp_dir/captured"

expected=$'1970-01-01 00:00:01 Alice Builder: Graphide alpha decision\n1970-01-01 00:00:04 Alice Builder: Graphide deadline Friday'
actual="$($script_dir/signal-redact.sh)"

if [[ "$actual" != "$expected" ]]; then
  printf 'unexpected extracted text\nexpected:\n%s\nactual:\n%s\n' "$expected" "$actual" >&2
  exit 1
fi

if [[ "$(cat "$SIGNAL_REDACT_TEST_CAPTURE")" != "$expected" ]]; then
  echo "extractor did not pipe the selected sender directly to privatellm-redact" >&2
  exit 1
fi

export SIGNAL_REDACT_TEST_SENDER=all
expected=$'1970-01-01 00:00:01 Alice Builder: Graphide alpha decision\n1970-01-01 00:00:02 Bob Writer: Bob side note\n1970-01-01 00:00:03 Me: My reply\n1970-01-01 00:00:04 Alice Builder: Graphide deadline Friday'
actual="$($script_dir/signal-redact.sh)"

if [[ "$actual" != "$expected" ]]; then
  printf 'unexpected complete transcript\nexpected:\n%s\nactual:\n%s\n' "$expected" "$actual" >&2
  exit 1
fi

echo "signal-redact tests passed"
