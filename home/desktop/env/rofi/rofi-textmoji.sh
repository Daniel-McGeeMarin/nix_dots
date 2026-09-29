# Body of rofi-textmoji; see the comment above rofiTextmoji in default.nix.
# TEXTMOJI_LIST is set by the wrapper to the store copy of textmojis.tsv
# (one "textmoji<TAB>keywords" per line).

list="${TEXTMOJI_LIST:?}"
state="${XDG_STATE_HOME:-$HOME/.local/state}/textmoji"
recent="$state/recent"
mkdir -p "$state"
touch "$recent"

# Rows are "textmoji   keywords", so typing a mood matches the keywords.
# Recently sent ones come first; rofi's -format i hands back the row number,
# so the textmoji itself never has to be parsed back out of the row.
rows="$(awk -F'\t' '
  FILENAME == ARGV[1] { if (!($0 in seen)) { seen[$0] = 1; order[++n] = $0 }; next }
  { kw[$1] = $2; all[++m] = $1 }
  END {
    for (i = 1; i <= n; i++) if (order[i] in kw) print order[i] "\t" kw[order[i]] " · recent"
    for (i = 1; i <= m; i++) if (!(all[i] in seen)) print all[i] "\t" kw[all[i]]
  }' "$recent" "$list")"

idx="$(printf '%s\n' "$rows" | sed 's/\t/     /' | rofi -dmenu -i -format i \
  -matching normal -p textmoji \
  -theme-str 'entry { width: 45%; placeholder: "Search textmojis: happy, smug, angry…"; }' \
  -theme-str 'listview { columns: 1; lines: 10; }')" || exit 0
[ -n "$idx" ] || exit 0

pick="$(printf '%s\n' "$rows" | sed -n "$((idx + 1))p" | cut -f1)"
[ -n "$pick" ] || exit 0

# Newest first, no repeats, last 30 kept.
{ printf '%s\n' "$pick"; grep -vxF -- "$pick" "$recent" || true; } | head -n 30 > "$recent.tmp"
mv "$recent.tmp" "$recent"

printf '%s' "$pick" | wl-copy
# Paste into whatever had focus before rofi opened. Terminals paste on
# Ctrl+Shift+V, everything else on Ctrl+V; the clipboard keeps the textmoji
# either way, so a missed paste is one Ctrl+V away.
sleep 0.15
class="$(hyprctl activewindow -j | jq -r '.class // ""')"
case "$class" in
  kitty|foot|footclient|Alacritty|org.wezfurlong.wezterm|com.mitchellh.ghostty)
    hyprctl dispatch sendshortcut "CTRL SHIFT,V," >/dev/null ;;
  *)
    hyprctl dispatch sendshortcut "CTRL,V," >/dev/null ;;
esac
