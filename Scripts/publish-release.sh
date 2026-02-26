#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <tag> [dmg_path] [repo]"
  echo "Example: $0 v0.1.0 dist/Castle-v0.1.0.dmg"
  exit 1
fi

TAG="$1"
DMG_PATH="${2:-dist/Castle-${TAG}.dmg}"
REPO="${3:-${CASTLE_GH_REPO:-dansc89/Castle}}"

if [[ ! -f "$DMG_PATH" ]]; then
  echo "DMG not found: $DMG_PATH"
  exit 1
fi

if gh release view "$TAG" --repo "$REPO" >/dev/null 2>&1; then
  echo "Release $TAG already exists. Uploading/replacing asset..."
  gh release upload "$TAG" "$DMG_PATH" --clobber --repo "$REPO"
else
  echo "Creating release $TAG and uploading DMG..."
  gh release create "$TAG" "$DMG_PATH" --generate-notes --repo "$REPO"
fi

echo "Done: https://github.com/$REPO/releases/tag/$TAG"
