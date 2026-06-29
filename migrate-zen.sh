#!/usr/bin/env bash
# One-time migration: move Zen profile from ~/.zen (pre-18.18.6b) to ~/.config/zen/default/
# Close Zen before running. After success, launch Zen once in safe mode.
# Then delete this file.

set -e

OLD="$HOME/.zen/543mgzlr.Default (release)"
NEW="$HOME/.config/zen/default"
OLD_PROFILES="$HOME/.zen/profiles.ini"

if [ ! -d "$OLD" ]; then
  echo "Old profile not found at $OLD, nothing to migrate."
  exit 0
fi

if [ -f "$NEW/places.sqlite" ]; then
  echo "Already migrated (places.sqlite exists in $NEW). Skipping."
  exit 0
fi

echo "Migrating Zen profile: ~/.zen → ~/.config/zen/default/"
mkdir -p "$NEW/chrome"

# Data files
for f in places.sqlite key4.db cert9.db logins.json cookies.sqlite \
          favicons.sqlite sessionstore.jsonlz4 webappsstore.sqlite \
          containers.json extension-settings.json extension-preferences.json \
          addonStartup.json.lz4; do
  [ -f "$OLD/$f" ] && cp "$OLD/$f" "$NEW/$f" && echo "  $f"
done

# Directories (skip chrome/ — Nix manages userChrome.css and mods there)
for d in storage browser-extension-data extensions bookmarkbackups datareporting; do
  [ -d "$OLD/$d" ] && cp -r "$OLD/$d" "$NEW/$d" && echo "  $d/"
done

# Update hardcoded paths inside copied files (README requirement for 18.18.6b migration)
OLD_PATH_ESC=$(printf '%s\n' "$OLD" | sed 's/[[\.*^$()+?{|]/\\&/g')
NEW_PATH_ESC=$(printf '%s\n' "$NEW" | sed 's/[[\.*^$()+?{|]/\\&/g')

for f in extensions.json pkcs11.txt chrome_debugger_profile/pkcs11.txt; do
  if [ -f "$NEW/$f" ]; then
    sed -i "s|$OLD_PATH_ESC|$NEW_PATH_ESC|g" "$NEW/$f" && echo "  updated paths in $f"
  fi
done

# Remove the locked Install section from ~/.zen/profiles.ini so zen-beta
# stops reading from the old location and falls through to ~/.config/zen/profiles.ini
if [ -f "$OLD_PROFILES" ]; then
  mv "$OLD_PROFILES" "${OLD_PROFILES}.pre-nix-migration"
  echo "  moved ~/.zen/profiles.ini → ~/.zen/profiles.ini.pre-nix-migration"
fi

echo ""
echo "Done. Next steps:"
echo "  1. Launch Zen once with: zen-beta --safe-mode"
echo "  2. Close safe mode, relaunch normally"
echo "  3. Delete this script"
