# Body of rofi-wifi; see the comment above rofiWifi in default.nix.
#
# Called three ways:
#   rofi-wifi                      rofi lists the rows (script mode)
#   ROFI_RETV=1 ROFI_INFO=<action> rofi picked a row
#   rofi-wifi --connect SSID SEC   the background connector, run after rofi
#                                  has closed so it can open its own password
#                                  prompt (two rofis cannot be open at once)

notify() { notify-send -a Wi-Fi -i network-wireless "$@" || true; }

# The saved NM profile whose SSID is $1. Profile names usually equal the SSID
# but not always ("4 dream (2.4)"), so ask each wireless profile.
profile_for() {
  local name type
  while IFS=: read -r name type; do
    [ "$type" = 802-11-wireless ] || continue
    if [ "$(nmcli -g 802-11-wireless.ssid connection show "$name" 2>/dev/null)" = "$1" ]; then
      printf '%s\n' "$name"
      return 0
    fi
  done < <(nmcli -t -e no -f NAME,TYPE connection show)
  return 1
}

ask_password() {
  rofi -dmenu -password -l 0 -p "Password for $1" </dev/null || true
}

# Open networks are usually a hotel/airport/café portal: if plain HTTP is
# being intercepted, open the sign-in page.
check_portal() {
  local body
  body=$(curl -fsS -m 5 http://detectportal.firefox.com/success.txt 2>/dev/null || true)
  if [ "$body" != success ]; then
    notify "Sign-in page" "$1 wants you to log in"
    setsid -f xdg-open http://neverssl.com >/dev/null 2>&1
  fi
}

connect() {
  local ssid=$1 security=$2 profile pw
  for _ in $(seq 50); do pgrep -x rofi >/dev/null || break; sleep 0.1; done

  notify "Connecting…" "$ssid"
  if profile=$(profile_for "$ssid"); then
    if nmcli connection up id "$profile" >/dev/null 2>&1; then
      notify "Connected" "$ssid"
      [ -n "$security" ] || check_portal "$ssid"
      return 0
    fi
    # Saved but refused: most often the password changed.
    [ -n "$security" ] || { notify -u critical "Could not connect" "$ssid"; return 1; }
    pw=$(ask_password "$ssid")
    [ -n "$pw" ] || return 1
    nmcli connection modify id "$profile" wifi-sec.psk "$pw"
    if nmcli connection up id "$profile" >/dev/null 2>&1; then
      notify "Connected" "$ssid"
    else
      notify -u critical "Could not connect" "$ssid: wrong password?"
    fi
    return 0
  fi

  if [ -z "$security" ]; then
    if nmcli device wifi connect "$ssid" >/dev/null 2>&1; then
      notify "Connected" "$ssid"
      check_portal "$ssid"
    else
      notify -u critical "Could not connect" "$ssid"
    fi
    return 0
  fi

  pw=$(ask_password "$ssid")
  [ -n "$pw" ] || return 1
  if nmcli device wifi connect "$ssid" password "$pw" >/dev/null 2>&1; then
    notify "Connected" "$ssid"
  else
    # Do not leave a half-made profile behind to be retried on every boot.
    if profile=$(profile_for "$ssid"); then nmcli connection delete id "$profile" >/dev/null 2>&1 || true; fi
    notify -u critical "Could not connect" "$ssid: wrong password?"
  fi
}

bars() {
  if   [ "$1" -ge 75 ]; then printf '󰤨'
  elif [ "$1" -ge 50 ]; then printf '󰤥'
  elif [ "$1" -ge 25 ]; then printf '󰤢'
  else printf '󰤟'
  fi
}

list() {
  printf '\0prompt\x1fWi-Fi\n'
  printf '\0markup-rows\x1ffalse\n'
  printf '\0no-custom\x1ftrue\n'

  if [ "$(nmcli radio wifi)" != enabled ]; then
    printf '\0message\x1fWi-Fi is off\n'
    printf '󰖩  Turn Wi-Fi on\0info\x1fon\n'
    return
  fi

  local current
  current=$(nmcli -t -e no -f IN-USE,SSID device wifi list --rescan no | sed -n 's/^\*://p' | head -n1)
  if [ -n "$current" ]; then
    printf '\0message\x1fConnected to %s\n' "$current"
  else
    printf '\0message\x1fNot connected\n'
  fi

  # Saved profile names, as a cheap "known network" mark for the list.
  local saved
  saved=$(nmcli -t -e no -f NAME,TYPE connection show | sed -n 's/:802-11-wireless$//p')

  # One row per SSID, strongest radio first; SSID is the last field, so any
  # colons in it stay in $ssid.
  local signal security ssid row lock mark active=0 n=0
  local -a rows=() infos=() i
  declare -A seen=()
  while IFS=: read -r signal security ssid; do
    [ -n "$ssid" ] || continue
    [ -z "${seen[$ssid]+x}" ] || continue
    seen[$ssid]=1
    lock=''; [ -n "$security" ] && [ "$security" != -- ] && lock='  '
    [ "$security" = -- ] && security=''
    mark=''; grep -qxF -- "$ssid" <<<"$saved" && mark='  · saved'
    row="$(bars "$signal")  $ssid$lock$mark"
    [ "$ssid" = "$current" ] && { row="$row  · connected"; active=$n; }
    rows+=("$row")
    infos+=("net"$'\t'"$ssid"$'\t'"$security")
    n=$((n + 1))
  done < <(nmcli -t -e no -f SIGNAL,SECURITY,SSID device wifi list --rescan no | sort -t: -k1,1nr)
  # Mode options go before the rows they describe.
  [ -z "$current" ] || printf '\0active\x1f%s\n' "$active"
  for i in "${!rows[@]}"; do
    printf '%s\0info\x1f%s\n' "${rows[$i]}" "${infos[$i]}"
  done

  printf '󰑐  Rescan\0info\x1frescan\n'
  printf '󰒓  Advanced settings\0info\x1feditor\n'
  printf '󰖪  Turn Wi-Fi off\0info\x1foff\n'
}

if [ "${1:-}" = --connect ]; then
  connect "$2" "${3:-}"
  exit 0
fi

if [ "${ROFI_RETV:-0}" = 1 ]; then
  case "${ROFI_INFO:-}" in
    net$'\t'*)
      IFS=$'\t' read -r _ ssid security <<<"$ROFI_INFO"
      setsid -f "$0" --connect "$ssid" "$security" >/dev/null 2>&1
      exit 0 ;;
    rescan)
      nmcli device wifi rescan >/dev/null 2>&1 || true
      sleep 2
      list ;;
    on)
      nmcli radio wifi on
      sleep 2
      list ;;
    off)
      nmcli radio wifi off
      exit 0 ;;
    editor)
      setsid -f nm-connection-editor >/dev/null 2>&1
      exit 0 ;;
  esac
  exit 0
fi

# Show the cached scan at once, and start a fresh one for the Rescan row.
setsid -f nmcli device wifi rescan >/dev/null 2>&1 || true
list
