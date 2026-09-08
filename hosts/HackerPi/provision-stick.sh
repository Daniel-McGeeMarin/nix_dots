#!/usr/bin/env bash
# Put the two runtime secrets onto a freshly flashed HackerPi stick.
#
# The image is built without any secrets in it (they would land in the nix
# store and in git); this writes them straight into the stick's root
# filesystem afterwards instead:
#
#   /var/lib/wifi-secrets            psk_home=<wifi password>
#   /var/lib/hackerboard/deploy-key  read-only GitHub deploy key
#
# Usage:
#   sudo ./provision-stick.sh /dev/sdX <wifi-password> [deploy-key-file]
#
# Run it AFTER dd-ing the image, BEFORE first boot. Without it the Pi still
# boots and serves the baked board on ethernet; Wi-Fi and self-update stay
# off until provisioned (the same files can be written over SSH later).
set -euo pipefail

dev="${1:?usage: provision-stick.sh /dev/sdX <wifi-password> [deploy-key-file]}"
psk="${2:?usage: provision-stick.sh /dev/sdX <wifi-password> [deploy-key-file]}"
keyfile="${3:-}"

# The sd-image layout: p1 firmware (FAT), p2 root (ext4).
root="${dev}2"
[ -b "$root" ] || root="${dev}p2"
[ -b "$root" ] || { echo "no root partition at ${dev}2 or ${dev}p2" >&2; exit 1; }

mnt=$(mktemp -d)
trap 'umount "$mnt" 2>/dev/null || true; rmdir "$mnt"' EXIT
mount "$root" "$mnt"

install -d -m 755 "$mnt/var/lib"
printf 'psk_home=%s\n' "$psk" > "$mnt/var/lib/wifi-secrets"
chmod 600 "$mnt/var/lib/wifi-secrets"
echo "wrote /var/lib/wifi-secrets"

if [ -n "$keyfile" ]; then
  install -d -m 755 "$mnt/var/lib/hackerboard"
  install -m 600 "$keyfile" "$mnt/var/lib/hackerboard/deploy-key"
  echo "wrote /var/lib/hackerboard/deploy-key"
else
  echo "no deploy key given; the board serves the baked build until one is provisioned"
fi

sync
echo "done -- unmounting"
