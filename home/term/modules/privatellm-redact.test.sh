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

line="$(jq -r '.messages[1].content' <<< "$payload")"
if [[ "${PRIVATE_LLM_TEST_FAIL_LINE:-}" == "$line" ]]; then
  echo 'simulated local model timeout' >&2
  exit 28
fi
case "$line" in
  *"deadline is Friday. damn")
    content='1'
    ;;
  *"called Mom"*)
    content='0'
    ;;
  *"Graphide relay"*)
    content='1'
    ;;
  *"malformed model output"*)
    printf '%s\n' '{"choices":[{"message":{"content":"not json"}}]}'
    exit 0
    ;;
  *)
    content='1'
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
export PRIVATE_LLM_STATE_DIR="$tmp_dir/state"
export PRIVATE_LLM_OUTPUT_DIR="$tmp_dir/output"

input=$'Graphide deadline is Friday. damn\n\nI called Mom about dinner\n\nShip the Graphide relay by Tuesday.\nmalformed model output\n'
expected=$'Graphide deadline is Friday. damn\n\nShip the Graphide relay by Tuesday.'

actual="$(printf '%s' "$input" | "$script_dir/privatellm-redact.sh" 2> "$tmp_dir/stderr")"

if [[ "$actual" != "$expected" ]]; then
  printf 'unexpected output\nexpected:\n%s\nactual:\n%s\n' "$expected" "$actual" >&2
  exit 1
fi

if [[ "$(cat "$PRIVATE_LLM_TEST_CLIPBOARD")" != "$expected" ]]; then
  echo "clipboard did not receive the complete redacted text" >&2
  exit 1
fi

completed_file="$(find "$PRIVATE_LLM_OUTPUT_DIR" -type f -name '*.txt')"
if [[ "$(cat "$completed_file")" != "$expected" ]]; then
  echo "completed output file did not receive the redacted text" >&2
  exit 1
fi

if ! grep -q 'invalid model response' "$tmp_dir/stderr"; then
  echo "malformed model output was not reported" >&2
  exit 1
fi

export PRIVATE_LLM_TEST_FAIL_LINE='Ship the Graphide relay by Tuesday.'
rm -rf "$PRIVATE_LLM_OUTPUT_DIR"
if printf '%s' "$input" | "$script_dir/privatellm-redact.sh" > /dev/null 2> "$tmp_dir/resume-stderr"; then
  echo "redactor unexpectedly succeeded after a simulated model timeout" >&2
  exit 1
fi

partial_file="$(find "$PRIVATE_LLM_OUTPUT_DIR" -type f -name '*.txt')"
if [[ "$(cat "$partial_file")" != 'Graphide deadline is Friday. damn' ]]; then
  echo "redactor did not save partial output after a model timeout" >&2
  exit 1
fi

if ! grep -q 'Run the same input again to resume' "$tmp_dir/resume-stderr"; then
  echo "redactor did not report how to resume after a model timeout" >&2
  exit 1
fi

unset PRIVATE_LLM_TEST_FAIL_LINE
actual="$(printf '%s' "$input" | "$script_dir/privatellm-redact.sh" 2> "$tmp_dir/resumed-stderr")"

if [[ "$actual" != "$expected" ]]; then
  printf 'unexpected resumed output\nexpected:\n%s\nactual:\n%s\n' "$expected" "$actual" >&2
  exit 1
fi

if [[ "$(cat "$partial_file")" != "$expected" ]]; then
  echo "resumed redactor did not complete the existing output file" >&2
  exit 1
fi

if find "$PRIVATE_LLM_STATE_DIR" -mindepth 1 -type d | grep -q .; then
  echo "redactor left a checkpoint after completing the resumed run" >&2
  exit 1
fi

echo "privatellm-redact tests passed"
