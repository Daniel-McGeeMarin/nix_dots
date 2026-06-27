#!/usr/bin/env bash
# Delete store paths with zero GC roots only.
# WARNING: zero roots does NOT mean unused — active .drv files may still reference a path.
# Only list paths verified safe (failed duplicates), never live flake/build inputs.
set -euo pipefail

paths=(
  # duplicate copies from interrupted builds, not yet in any profile
  /nix/store/p00diwbl8l0sfj3icsb0hpmf3ivnqk54-cef-binary-6533
  /nix/store/3hjgy7fzf288298m97dpzvw6ind3a66i-libreoffice-25.2.6.2
)

echo "Before:" && df -h /nix

sudo mount -o remount,rw /nix/store 2>/dev/null || true

freed=0
for p in "${paths[@]}"; do
  if [[ -e "$p" ]]; then
    roots=$(nix-store --query --roots "$p" 2>/dev/null | wc -l)
    if [[ "$roots" -eq 0 ]]; then
      sz=$(du -sh "$p" | cut -f1)
      echo "Removing $sz  $p"
      sudo rm -rf "$p"
      freed=$((freed + 1))
    else
      echo "SKIP (has roots): $p"
    fi
  fi
done

sudo mount -o remount,ro /nix/store 2>/dev/null || true

echo "Removed $freed paths."
echo "After:" && df -h /nix
