#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

APP_NAME="Castle"
BUNDLE_ID="com.drawbridge.castle"
BUILD_DIR=".build/arm64-apple-macosx/release"
BIN_PATH="$BUILD_DIR/$APP_NAME"
DIST_DIR="dist"
APP_DIR="$DIST_DIR/$APP_NAME.app"
INSTALL_ROOT="${CASTLE_INSTALL_ROOT:-/Users/danielnguyen/Applications}"
INSTALL_APP_DIR="$INSTALL_ROOT/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
PLIST_PATH="$CONTENTS_DIR/Info.plist"
ICONSET_DIR="Assets/AppIcon.iconset"
ICON_SOURCE_PNG="${CASTLE_ICON_SOURCE_PNG:-Assets/AppIcon.source.png}"
ICON_USE_AS_IS="${CASTLE_ICON_USE_AS_IS:-0}"
ICON_FILE_NAME="Castle"
ICON_ICNS_PATH="$RESOURCES_DIR/$ICON_FILE_NAME.icns"
VERSION_TAG="${CASTLE_VERSION_TAG:-v0.1.0}"
APP_VERSION="${VERSION_TAG#v}"
BUILD_NUMBER="${CASTLE_BUILD_NUMBER:-1}"
SIGN_IDENTITY="${CASTLE_CODESIGN_IDENTITY:-}"

echo "Building release binary..."
swift build -c release

if [[ ! -x "$BIN_PATH" ]]; then
  echo "Expected binary not found at $BIN_PATH"
  exit 1
fi

echo "Creating app bundle..."
rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
cp "$BIN_PATH" "$MACOS_DIR/$APP_NAME"
chmod +x "$MACOS_DIR/$APP_NAME"

echo "Generating app icon..."
if [[ -f "$ICON_SOURCE_PNG" ]]; then
  mkdir -p "$ICONSET_DIR"
  if [[ "$ICON_USE_AS_IS" == "1" ]]; then
    sips -z 1024 1024 "$ICON_SOURCE_PNG" --out "$ICONSET_DIR/icon_1024x1024.png" >/dev/null
  else
    swift Scripts/prepare-icon.swift "$ICON_SOURCE_PNG" "$ICONSET_DIR/icon_1024x1024.png"
  fi
elif [[ ! -f "$ICONSET_DIR/icon_1024x1024.png" ]]; then
  swift Scripts/generate-icon.swift
fi
for sz in 16 32 64 128 256 512; do
  sips -z "$sz" "$sz" "$ICONSET_DIR/icon_1024x1024.png" --out "$ICONSET_DIR/icon_${sz}x${sz}.png" >/dev/null
done
cp "$ICONSET_DIR/icon_32x32.png" "$ICONSET_DIR/icon_16x16@2x.png"
cp "$ICONSET_DIR/icon_64x64.png" "$ICONSET_DIR/icon_32x32@2x.png"
cp "$ICONSET_DIR/icon_256x256.png" "$ICONSET_DIR/icon_128x128@2x.png"
cp "$ICONSET_DIR/icon_512x512.png" "$ICONSET_DIR/icon_256x256@2x.png"
cp "$ICONSET_DIR/icon_1024x1024.png" "$ICONSET_DIR/icon_512x512@2x.png"
iconutil -c icns "$ICONSET_DIR" -o "$ICON_ICNS_PATH"

cat > "$PLIST_PATH" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleIconFile</key>
  <string>$ICON_FILE_NAME</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$APP_VERSION</string>
  <key>CFBundleVersion</key>
  <string>$BUILD_NUMBER</string>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>CFBundleDocumentTypes</key>
  <array>
    <dict>
      <key>CFBundleTypeName</key>
      <string>DXF Drawing</string>
      <key>LSItemContentTypes</key>
      <array>
        <string>com.drawbridge.castle.dxf</string>
      </array>
      <key>CFBundleTypeExtensions</key>
      <array>
        <string>dxf</string>
      </array>
      <key>CFBundleTypeRole</key>
      <string>Editor</string>
      <key>LSHandlerRank</key>
      <string>Owner</string>
    </dict>
    <dict>
      <key>CFBundleTypeName</key>
      <string>PDF Document</string>
      <key>CFBundleTypeExtensions</key>
      <array>
        <string>pdf</string>
      </array>
      <key>CFBundleTypeRole</key>
      <string>Viewer</string>
      <key>LSHandlerRank</key>
      <string>Alternate</string>
    </dict>
  </array>
  <key>UTExportedTypeDeclarations</key>
  <array>
    <dict>
      <key>UTTypeIdentifier</key>
      <string>com.drawbridge.castle.dxf</string>
      <key>UTTypeDescription</key>
      <string>DXF Drawing</string>
      <key>UTTypeConformsTo</key>
      <array>
        <string>public.text</string>
        <string>public.data</string>
      </array>
      <key>UTTypeTagSpecification</key>
      <dict>
        <key>public.filename-extension</key>
        <array>
          <string>dxf</string>
          <string>DXF</string>
        </array>
        <key>public.mime-type</key>
        <array>
          <string>image/vnd.dxf</string>
        </array>
      </dict>
    </dict>
  </array>
</dict>
</plist>
PLIST

if [[ -n "$SIGN_IDENTITY" ]]; then
  echo "Signing app bundle with identity: $SIGN_IDENTITY"
  codesign --force --deep --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP_DIR"
else
  echo "No CASTLE_CODESIGN_IDENTITY set; using ad-hoc signing."
  codesign --force --deep --sign - "$APP_DIR"
fi

codesign --verify --deep --strict --verbose=2 "$APP_DIR"

echo "Syncing latest build to $INSTALL_APP_DIR ..."
mkdir -p "$INSTALL_ROOT"
rsync -a --delete "$APP_DIR/" "$INSTALL_APP_DIR/"

echo "Done: $APP_DIR"
echo "Launch with: open \"$APP_DIR\""
echo "Installed latest to: $INSTALL_APP_DIR"
