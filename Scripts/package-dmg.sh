#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 2 ]]; then
  echo "Usage: $0 <app_path> <output_dmg> [volume_name]"
  exit 1
fi

APP_PATH="$1"
OUTPUT_DMG="$2"
VOLUME_NAME="${3:-Castle}"
APP_BASENAME="$(basename \"$APP_PATH\")"

if [[ ! -d "$APP_PATH" ]]; then
  echo "App bundle not found: $APP_PATH"
  exit 1
fi

HAS_CREATE_DMG=0
if command -v create-dmg >/dev/null 2>&1; then
  HAS_CREATE_DMG=1
fi

TMP_DIR="$(mktemp -d)"
STAGING_DIR="$TMP_DIR/staging"
BACKGROUND_PATH="$TMP_DIR/background.png"
APPS_ALIAS_PATH="$TMP_DIR/Applications.alias"
cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

mkdir -p "$STAGING_DIR"
cp -R "$APP_PATH" "$STAGING_DIR/"
swift Scripts/generate-dmg-background.swift "$BACKGROUND_PATH"

osascript <<EOF >/dev/null 2>/dev/null || true
tell application "Finder"
  set aliasContainer to POSIX file "$TMP_DIR" as alias
  make new alias file at aliasContainer to POSIX file "/Applications" with properties {name:"Applications.alias"}
end tell
EOF
if [[ ! -e "$APPS_ALIAS_PATH" ]]; then
  ln -s /Applications "$APPS_ALIAS_PATH"
fi

rm -f "$OUTPUT_DMG"
mkdir -p "$(dirname "$OUTPUT_DMG")"

if [[ "$HAS_CREATE_DMG" == "1" ]]; then
  set +e
  create-dmg \
    --volname "$VOLUME_NAME" \
    --window-pos 120 120 \
    --window-size 860 520 \
    --background "$BACKGROUND_PATH" \
    --icon-size 128 \
    --icon "$APP_BASENAME" 200 285 \
    --hide-extension "$APP_BASENAME" \
    --add-file "Applications" "$APPS_ALIAS_PATH" 650 285 \
    "$OUTPUT_DMG" \
    "$STAGING_DIR"
  CREATE_DMG_EXIT=$?
  set -e
  if [[ $CREATE_DMG_EXIT -eq 0 ]]; then
    echo "Created DMG: $OUTPUT_DMG"
    exit 0
  fi
  echo "create-dmg failed ($CREATE_DMG_EXIT), falling back to hdiutil packaging..."
fi

# Fallback: deterministic DMG without Finder scripting.
cp -R "$APPS_ALIAS_PATH" "$STAGING_DIR/Applications"
hdiutil create \
  -volname "$VOLUME_NAME" \
  -srcfolder "$STAGING_DIR" \
  -ov \
  -format UDZO \
  "$OUTPUT_DMG" >/dev/null

echo "Created DMG: $OUTPUT_DMG"
