# Body of rofi-artifacts; see the comment above rofiArtifacts in default.nix.
if [ "${ROFI_RETV:-0}" = 1 ]; then
  if [ -n "${ROFI_INFO:-}" ]; then
    setsid -f xdg-open "$ROFI_INFO" >/dev/null 2>&1
  fi
  exit 0
fi
printf '\0prompt\x1fArtifacts\n'
for base in http://xiaserver:8420 http://10.0.0.35:8420; do
  if json=$(curl -fsS -m 3 "$base/index.json" 2>/dev/null); then
    printf 'All artifacts (index)\0info\x1f%s/\n' "$base"
    jq -r --arg base "$base" '.[] |
      "\(.title)  ·  \(.updated[:10])\(if .source != "" then "  ·  " + .source else "" end)\u0000info\u001f\($base)\(.url)\u001fmeta\u001f\(.slug) \(.repo) \(.author) \(.description)"' <<<"$json"
    exit 0
  fi
done
printf 'Artifact server unreachable (xiaserver:8420)\0nonselectable\x1ftrue\n'
