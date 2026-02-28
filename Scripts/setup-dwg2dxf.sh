#!/usr/bin/env bash
set -euo pipefail

REPO_URL="https://github.com/codelibs/libdxfrw.git"
SOURCE_DIR="${CASTLE_DWG2DXF_SOURCE:-$HOME/Library/Application Support/Castle/Converters/libdxfrw}"
BUILD_DIR="$SOURCE_DIR/build"
INSTALL_ROOT="${CASTLE_DWG_CONVERTER_ROOT:-$HOME/Library/Application Support/Castle/Converters}"
INSTALL_BIN="$INSTALL_ROOT/dwg2dxf/dwg2dxf"

if ! command -v git >/dev/null 2>&1; then
  echo "git is required to clone libdxfrw." >&2
  exit 1
fi
if ! command -v cmake >/dev/null 2>&1; then
  echo "cmake is required to build dwg2dxf (install via 'brew install cmake' or equivalent)." >&2
  exit 1
fi

mkdir -p "$(dirname "$SOURCE_DIR")"
if [ -d "$SOURCE_DIR/.git" ]; then
  echo "Updating libdxfrw source in $SOURCE_DIR"
  git -C "$SOURCE_DIR" fetch origin
  git -C "$SOURCE_DIR" reset --hard origin/main
else
  echo "Cloning libdxfrw into $SOURCE_DIR"
  git clone "$REPO_URL" "$SOURCE_DIR"
fi

mkdir -p "$BUILD_DIR"
cmake -S "$SOURCE_DIR" -B "$BUILD_DIR" -DCMAKE_BUILD_TYPE=Release
cmake --build "$BUILD_DIR" --target dwg2dxf

BUILT_BIN="$BUILD_DIR/dwg2dxf/dwg2dxf"
if [ ! -x "$BUILT_BIN" ]; then
  echo "sh: unable to find dwg2dxf binary at $BUILT_BIN" >&2
  exit 1
fi

mkdir -p "$(dirname "$INSTALL_BIN")"
cp "$BUILT_BIN" "$INSTALL_BIN"
chmod +x "$INSTALL_BIN"

echo "dwg2dxf installed to $INSTALL_BIN"
