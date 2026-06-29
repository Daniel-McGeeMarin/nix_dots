#!/usr/bin/env bash
# One-time migration: copy profile data from the old ~/.zen profile
# into the new HM-managed location at ~/.config/zen/default/
# Run once after nixswitch, then delete this file.

OLD="$HOME/.zen/543mgzlr.Default (release)"
NEW="$HOME/.config/zen/default"

mkdir -p "$NEW/chrome"

if [ ! -d "$OLD" ]; then
  echo "Old profile not found at $OLD, nothing to migrate."
  exit 0
fi

if [ -f "$NEW/places.sqlite" ]; then
  echo "New profile already has data at $NEW, skipping migration."
  exit 0
fi

echo "Migrating Zen profile data from:"
echo "  $OLD"
echo "  → $NEW"

for f in places.sqlite key4.db logins.json cookies.sqlite favicons.sqlite \
          sessionstore.jsonlz4 webappsstore.sqlite; do
  if [ -f "$OLD/$f" ]; then
    cp "$OLD/$f" "$NEW/$f" && echo "  copied $f"
  fi
done

for d in storage browser-extension-data extensions; do
  if [ -d "$OLD/$d" ]; then
    cp -r "$OLD/$d" "$NEW/$d" && echo "  copied $d/"
  fi
done

echo "Done."
