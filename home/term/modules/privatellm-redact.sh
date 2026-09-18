#!/usr/bin/env bash
set -euo pipefail

endpoint="${PRIVATE_LLM_URL:-http://127.0.0.1:8090/v1/chat/completions}"
model="${PRIVATE_LLM_MODEL:-gemma3}"
max_line_chars=1500
state_root="${PRIVATE_LLM_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/privatellm-redact}"
output_dir="${PRIVATE_LLM_OUTPUT_DIR:-${XDG_DOCUMENTS_DIR:-$HOME/Documents}/Redacted Signal Transcripts}"

system_prompt=$(cat <<'PROMPT'
Reply with exactly 0 or 1.

Is this message personal or work related?

Return 0 for anything personal, political, or seriously negative, hostile, or
derogatory. Innocuous swears such as "fuck" and "damn" are allowed. Return 1
for work-related content.
PROMPT
)

if [[ -t 0 ]]; then
  printf '%s\n' \
    'Paste the full chat below, then press Ctrl-D on a new line to redact it:' >&2
fi

input="$(cat)"
if [[ ! "$input" =~ [^[:space:]] ]]; then
  echo "error: no text was provided" >&2
  exit 1
fi

umask 077
input_hash="$(printf '%s' "$input" | sha256sum | awk '{print $1}')"
checkpoint_dir="$state_root/v2-$input_hash"
mkdir -p "$checkpoint_dir"
resume_at=0
if [[ -f "$checkpoint_dir/next" ]]; then
  resume_at="$(< "$checkpoint_dir/next")"
  if [[ ! "$resume_at" =~ ^[0-9]+$ ]]; then
    echo "error: invalid local redaction checkpoint at $checkpoint_dir" >&2
    exit 1
  fi
  echo "resuming redaction at line $((resume_at + 1))" >&2
fi

mkdir -p "$output_dir"
if [[ -f "$checkpoint_dir/output_path" ]]; then
  output_path="$(< "$checkpoint_dir/output_path")"
  if [[ ! "$output_path" == "$output_dir"/* ]]; then
    echo "error: invalid local redaction output path at $checkpoint_dir" >&2
    exit 1
  fi
else
  output_path="$(mktemp "$output_dir/signal-redacted-$(date '+%Y-%m-%d_%H-%M-%S')-XXXXXX.txt")"
  printf '%s\n' "$output_path" > "$checkpoint_dir/output_path"
fi

checkpoint_line_path() {
  printf '%s/line-%08d' "$checkpoint_dir" "$1"
}

save_line() {
  local line_index="$1"
  local value="$2"
  local target temp
  target="$(checkpoint_line_path "$line_index")"
  temp="$target.tmp"
  printf '%s' "$value" > "$temp"
  mv "$temp" "$target"
}

save_progress() {
  local next="$1"
  local temp="$checkpoint_dir/next.tmp"
  printf '%s\n' "$next" > "$temp"
  mv "$temp" "$checkpoint_dir/next"
}

write_output() {
  local rendered=""
  local blank_pending=false
  local rendered_line

  for rendered_line in "${output_lines[@]}"; do
    if [[ -z "$rendered_line" ]]; then
      if [[ -n "$rendered" ]]; then
        blank_pending=true
      fi
      continue
    fi

    if [[ -n "$rendered" ]]; then
      if [[ "$blank_pending" == "true" ]]; then
        rendered+=$'\n\n'
      else
        rendered+=$'\n'
      fi
    fi
    rendered+="$rendered_line"
    blank_pending=false
  done

  printf '%s\n' "$rendered" > "$output_path.tmp"
  mv "$output_path.tmp" "$output_path"
}

mapfile -t lines <<< "$input"
total="${#lines[@]}"
output_lines=()

for index in "${!lines[@]}"; do
  line="${lines[$index]}"
  number=$((index + 1))

  if (( index < resume_at )); then
    saved_line="$(checkpoint_line_path "$index")"
    if [[ -e "$saved_line" ]]; then
      output_lines+=("$(< "$saved_line")")
    fi
    continue
  fi

  if [[ -z "$line" ]]; then
    output_lines+=("")
    save_line "$index" ""
    save_progress "$number"
    continue
  fi

  if (( ${#line} > max_line_chars )); then
    echo "[$number/$total] line exceeds $max_line_chars characters; withholding line" >&2
    save_progress "$number"
    continue
  fi

  echo "[$number/$total] checking line..." >&2
  payload="$(jq -cn \
    --arg model "$model" \
    --arg system "$system_prompt" \
    --arg content "$line" \
    '{
      model: $model,
      messages: [
        {role: "system", content: $system},
        {role: "user", content: $content}
      ],
      temperature: 0,
      max_tokens: 1,
      stream: false
    }')"

  decision=""
  if ! response="$(curl --fail-with-body --silent --show-error --connect-timeout 5 --max-time 30 \
      -H 'Content-Type: application/json' \
      --data-binary "$payload" \
      "$endpoint")"; then
    echo "error: local model request failed on line $number/$total" >&2
    write_output
    echo "Partial redacted output saved to $output_path" >&2
    echo "Progress through line $index is saved locally. Run the same input again to resume." >&2
    exit 1
  fi

  decision="$(jq -er '
    .choices[0].message.content
    | strings
    | gsub("^\\s+|\\s+$"; "")
    | select(. == "0" or . == "1")
  ' <<< "$response" 2>/dev/null || true)"

  if [[ -z "$decision" ]]; then
    if [[ "${PRIVATE_LLM_DEBUG_RANGES:-0}" == "1" ]]; then
      jq -r '"[debug] raw model content: " + (.choices[0].message.content // "(missing)")' <<< "$response" >&2 || true
    fi
    echo "[$number/$total] invalid model response; withholding line" >&2
    save_progress "$number"
    continue
  fi

  if [[ "$decision" == "0" ]]; then
    save_progress "$number"
    continue
  fi

  output_lines+=("$line")
  save_line "$index" "$line"
  save_progress "$number"

  if (( number % 100 == 0 )); then
    write_output
  fi
done

write_output
result="$(< "$output_path")"

printf '%s\n' "$result"
if [[ "${PRIVATE_LLM_NO_CLIPBOARD:-0}" != "1" ]] && command -v wl-copy >/dev/null 2>&1; then
  printf '%s' "$result" | wl-copy
fi
if command -v notify-send >/dev/null 2>&1; then
  notify-send "privatellm-redact" "Done -- saved redacted text to $(basename "$output_path") ($total lines checked)." >/dev/null 2>&1 || true
fi

echo "Redacted output saved to $output_path" >&2

rm -rf "$checkpoint_dir"

unset input input_hash checkpoint_dir resume_at output_dir output_path lines output_lines line response decision result payload saved_line
