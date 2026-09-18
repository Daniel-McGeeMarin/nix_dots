#!/usr/bin/env bash
set -euo pipefail

signal_db="${SIGNAL_DB:-$HOME/.config/Signal/sql/db.sqlite}"
signal_config="${SIGNAL_CONFIG:-$HOME/.config/Signal/config.json}"
sqlite_bin="${SIGNAL_SQLITE_BIN:-sqlcipher}"
plaintext_db="${SIGNAL_PLAINTEXT_DB:-0}"
before="${SIGNAL_REDACT_BEFORE:-}"

if [[ ! -r "$signal_db" ]]; then
  echo "error: Signal database is not readable at $signal_db" >&2
  exit 1
fi

db_key=""
if [[ "$plaintext_db" != "1" ]]; then
  if [[ ! -r "$signal_config" ]]; then
    echo "error: Signal config is not readable at $signal_config" >&2
    exit 1
  fi
  db_key="$(jq -er '.key | select(type == "string")' "$signal_config")"
  if [[ ! "$db_key" =~ ^[[:xdigit:]]{64}$ ]]; then
    echo "error: Signal config contains no valid 256-bit database key" >&2
    exit 1
  fi
fi

run_sql() {
  local query="$1"

  if [[ "$plaintext_db" == "1" ]]; then
    {
      printf '.bail on\n.headers off\n.mode tabs\nPRAGMA query_only = ON;\n'
      printf '%s\n' "$query"
    } | "$sqlite_bin" -readonly -batch "$signal_db"
    return
  fi

  {
    # Suppress SQLCipher's "ok" response so it cannot become a picker row or
    # flow into the transcript. The key is passed over stdin, never argv.
    printf '.bail on\n.output /dev/null\nPRAGMA key = "x\x27%s\x27";\n.output stdout\n' "$db_key"
    printf '.headers off\n.mode tabs\nPRAGMA query_only = ON;\n'
    printf '%s\n' "$query"
  } | "$sqlite_bin" -readonly -batch "$signal_db"
}

to_sql_hex() {
  printf '%s' "$1" | od -An -v -tx1 | tr -d ' \n'
}

before_filter=""
if [[ -n "$before" ]]; then
  if [[ ! "$before" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}\ [0-9]{2}:[0-9]{2}:[0-9]{2}$ ]]; then
    echo "error: SIGNAL_REDACT_BEFORE must be YYYY-MM-DD HH:MM:SS" >&2
    exit 1
  fi
  before_seconds="$(date -d "$before" +%s)"
  before_milliseconds=$((before_seconds * 1000))
  before_filter="AND COALESCE(m.timestamp, m.sent_at, m.received_at_ms, 0) < $before_milliseconds"
fi

chat_query=$(cat <<'SQL'
SELECT
  c.id,
  replace(replace(replace(
    COALESCE(
      NULLIF(c.name, ''),
      NULLIF(c.profileFullName, ''),
      NULLIF(trim(COALESCE(c.profileName, '') || ' ' || COALESCE(c.profileFamilyName, '')), ''),
      NULLIF(c.e164, ''),
      'Unknown chat'
    ), char(9), ' '), char(10), ' '), char(13), ' '),
  COALESCE(c.type, 'unknown'),
  COALESCE(
    datetime(MAX(COALESCE(m.timestamp, m.sent_at, m.received_at_ms)) / 1000, 'unixepoch', 'localtime'),
    'unknown date'
  ),
  COUNT(*)
FROM conversations AS c
JOIN messages AS m ON m.conversationId = c.id
WHERE NULLIF(trim(m.body), '') IS NOT NULL
  AND COALESCE(m.isErased, 0) = 0
GROUP BY c.id
ORDER BY MAX(COALESCE(m.timestamp, m.sent_at, m.received_at_ms, 0)) DESC;
SQL
)

if ! chat_choice="$(
  run_sql "$chat_query" |
    fzf --delimiter=$'\t' --with-nth=2,3,4,5 \
      --header=$'Chat\tType\tLast text\tMessages' \
      --prompt='Signal chat> '
)"; then
  echo "Signal chat selection cancelled." >&2
  exit 1
fi

chat_id="${chat_choice%%$'\t'*}"
if [[ -z "$chat_id" || ! "$chat_id" =~ ^[A-Za-z0-9._:+-]+$ ]]; then
  echo "error: selected chat has an unexpected identifier" >&2
  exit 1
fi
chat_hex="$(to_sql_hex "$chat_id")"

sender_query="
SELECT sender_key, sender_name, message_count
FROM (
  SELECT
    'all' AS sender_key,
    'Both' AS sender_name,
    COUNT(*) AS message_count,
    -1 AS sort_order
  FROM messages
  WHERE conversationId = CAST(X'$chat_hex' AS TEXT)
    AND NULLIF(trim(body), '') IS NOT NULL
    AND COALESCE(isErased, 0) = 0
  HAVING COUNT(*) > 0

  UNION ALL

  SELECT
    'outgoing:me' AS sender_key,
    'Me' AS sender_name,
    COUNT(*) AS message_count,
    0 AS sort_order
  FROM messages
  WHERE conversationId = CAST(X'$chat_hex' AS TEXT)
    AND type = 'outgoing'
    AND NULLIF(trim(body), '') IS NOT NULL
    AND COALESCE(isErased, 0) = 0
  HAVING COUNT(*) > 0

  UNION ALL

  SELECT
    'incoming:' || COALESCE(m.sourceServiceId, m.source, 'unknown') AS sender_key,
    replace(replace(replace(
      COALESCE(
        NULLIF(MAX(s.profileFullName), ''),
        NULLIF(trim(COALESCE(MAX(s.profileName), '') || ' ' || COALESCE(MAX(s.profileFamilyName), '')), ''),
        NULLIF(MAX(s.name), ''),
        NULLIF(MAX(m.source), ''),
        NULLIF(MAX(m.sourceServiceId), ''),
        'Unknown sender'
      ), char(9), ' '), char(10), ' '), char(13), ' ') AS sender_name,
    COUNT(*) AS message_count,
    1 AS sort_order
  FROM messages AS m
  LEFT JOIN conversations AS s
    ON s.serviceId = m.sourceServiceId
    OR (m.sourceServiceId IS NULL AND s.e164 = m.source)
  WHERE m.conversationId = CAST(X'$chat_hex' AS TEXT)
    AND m.type = 'incoming'
    AND NULLIF(trim(m.body), '') IS NOT NULL
    AND COALESCE(m.isErased, 0) = 0
  GROUP BY COALESCE(m.sourceServiceId, m.source, 'unknown')
)
ORDER BY sort_order, sender_name;"

if ! sender_choice="$(
  run_sql "$sender_query" |
    fzf --delimiter=$'\t' --with-nth=2,3 \
      --header=$'Sender\tMessages' \
      --prompt='Sender> '
)"; then
  echo "Signal sender selection cancelled." >&2
  exit 1
fi

sender_key="${sender_choice%%$'\t'*}"
case "$sender_key" in
  all)
    sender_filter='1 = 1'
    ;;
  outgoing:me)
    sender_filter="m.type = 'outgoing'"
    ;;
  incoming:*)
    sender_id="${sender_key#incoming:}"
    if [[ -z "$sender_id" || ! "$sender_id" =~ ^[A-Za-z0-9._:+-]+$ ]]; then
      echo "error: selected sender has an unexpected identifier" >&2
      exit 1
    fi
    sender_hex="$(to_sql_hex "$sender_id")"
    sender_filter="m.type = 'incoming' AND COALESCE(m.sourceServiceId, m.source, 'unknown') = CAST(X'$sender_hex' AS TEXT)"
    ;;
  *)
    echo "error: selected sender has an unexpected type" >&2
    exit 1
    ;;
esac

extract_query="
.mode list
SELECT
  datetime(COALESCE(m.timestamp, m.sent_at, m.received_at_ms, 0) / 1000, 'unixepoch', 'localtime')
    || ' ' ||
  CASE
    WHEN m.type = 'outgoing' THEN 'Me'
    ELSE replace(replace(replace(
      COALESCE(
        NULLIF(s.profileFullName, ''),
        NULLIF(trim(COALESCE(s.profileName, '') || ' ' || COALESCE(s.profileFamilyName, '')), ''),
        NULLIF(s.name, ''),
        NULLIF(m.source, ''),
        NULLIF(m.sourceServiceId, ''),
        'Unknown sender'
      ), char(9), ' '), char(10), ' '), char(13), ' ')
  END || ': ' ||
  replace(replace(m.body, char(13), ''), char(10), char(10) || '    ')
FROM messages AS m
LEFT JOIN conversations AS s
  ON s.serviceId = m.sourceServiceId
  OR (m.sourceServiceId IS NULL AND s.e164 = m.source)
WHERE m.conversationId = CAST(X'$chat_hex' AS TEXT)
  AND $sender_filter
  $before_filter
  AND NULLIF(trim(m.body), '') IS NOT NULL
  AND COALESCE(m.isErased, 0) = 0
ORDER BY COALESCE(m.timestamp, m.sent_at, m.received_at_ms, 0), m.rowid;"

run_sql "$extract_query" | privatellm-redact

unset db_key before before_seconds before_milliseconds before_filter chat_choice chat_id chat_hex sender_choice sender_key sender_id sender_hex sender_filter extract_query
