#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

cat > "$tmp_dir/curl" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail

payload=""
while (( $# )); do
  if [[ "$1" == "--data-binary" ]]; then
    payload="$2"
    shift 2
  else
    shift
  fi
done

message="$(jq -r '.messages[1].content' <<< "$payload")"
line="$(jq -nr --arg message "$message" '$message | capture("^ORIGINAL LINE:\\n(?<line>[^\\n]*)").line')"
case "$line" in
  *"deadline is Friday. damn")
    start="$(jq -nr --arg line "$line" '$line | index("damn")')"
    content="$(jq -cn --argjson start "$start" '{remove_entire_line:false,spans:[{start:$start,end:($start + 4),category:"profanity"}]}')"
    ;;
  *"called Mom"*)
    content='{"remove_entire_line":true,"spans":[]}'
    ;;
  *"Graphide relay"*)
    content=$'```json\n{"remove_entire_line":false,"spans":[]}\n```'
    ;;
  *"malformed model output"*)
    printf '%s\n' '{"choices":[{"message":{"content":"not json"}}]}'
    exit 0
    ;;
  *)
    content='{"remove_entire_line":false,"spans":[]}'
    ;;
esac

jq -cn --arg content "$content" '{choices:[{message:{content:$content},finish_reason:"stop"}]}'
MOCK

cat > "$tmp_dir/wl-copy" <<'MOCK'
#!/usr/bin/env bash
cat > "$PRIVATE_LLM_TEST_CLIPBOARD"
MOCK

cat > "$tmp_dir/notify-send" <<'MOCK'
#!/usr/bin/env bash
exit 0
MOCK

chmod +x "$tmp_dir/curl" "$tmp_dir/wl-copy" "$tmp_dir/notify-send"

export PATH="$tmp_dir:$PATH"
export PRIVATE_LLM_TEST_CLIPBOARD="$tmp_dir/clipboard"

input=$'Graphide deadline is Friday. damn\n\nI called Mom about dinner\n\nShip the Graphide relay by Tuesday.\nmalformed model output\n'
expected=$'Graphide deadline is Friday.\n\nShip the Graphide relay by Tuesday.'

actual="$(printf '%s' "$input" | "$script_dir/privatellm-redact.sh" 2> "$tmp_dir/stderr")"

if [[ "$actual" != "$expected" ]]; then
  printf 'unexpected output\nexpected:\n%s\nactual:\n%s\n' "$expected" "$actual" >&2
  exit 1
fi

if [[ "$(cat "$PRIVATE_LLM_TEST_CLIPBOARD")" != "$expected" ]]; then
  echo "clipboard did not receive the complete redacted text" >&2
  exit 1
fi

if ! grep -q 'withholding line' "$tmp_dir/stderr"; then
  echo "malformed model output was not reported" >&2
  exit 1
fi

echo "privatellm-redact tests passed"
