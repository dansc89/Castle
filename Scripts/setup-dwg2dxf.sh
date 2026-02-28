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
  echo "cmake is required to build dwg2dxf (install via 'brew install cmake')." >&2
  exit 1
fi

mkdir -p "$(dirname "$SOURCE_DIR")"
if [ -d "$SOURCE_DIR/.git" ]; then
  echo "Updating libdxfrw source in $SOURCE_DIR"
  git -C "$SOURCE_DIR" fetch origin
  DEFAULT_BRANCH=$(git -C "$SOURCE_DIR" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's#^origin/##')
  DEFAULT_BRANCH=${DEFAULT_BRANCH:-master}
  git -C "$SOURCE_DIR" checkout "$DEFAULT_BRANCH"
  git -C "$SOURCE_DIR" reset --hard "origin/$DEFAULT_BRANCH"
else
  echo "Cloning libdxfrw into $SOURCE_DIR"
  git clone "$REPO_URL" "$SOURCE_DIR"
  DEFAULT_BRANCH=$(git -C "$SOURCE_DIR" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's#^origin/##')
  DEFAULT_BRANCH=${DEFAULT_BRANCH:-master}
  git -C "$SOURCE_DIR" checkout "$DEFAULT_BRANCH"
fi

mkdir -p "$BUILD_DIR"
cmake -S "$SOURCE_DIR" -B "$BUILD_DIR" -DCMAKE_BUILD_TYPE=Release
cmake --build "$BUILD_DIR" --target dxfrw

DXFRW_LIB=$(find "$BUILD_DIR" -maxdepth 2 -name 'libdxfrw.*' | head -n 1)
if [ -z "$DXFRW_LIB" ]; then
  echo "Unable to locate libdxfrw library in $BUILD_DIR" >&2
  exit 1
fi

DWG_BIN_DIR="$BUILD_DIR/dwg2dxf"
mkdir -p "$DWG_BIN_DIR"
clang++ \
  -std=c++17 \
  -I"$SOURCE_DIR/include" \
  -I"$SOURCE_DIR/src" \
  -I"$SOURCE_DIR/src/intern" \
  "$SOURCE_DIR/dwg2dxf/main.cpp" \
  "$SOURCE_DIR/dwg2dxf/dx_iface.cpp" \
  "$DXFRW_LIB" \
  -liconv \
  -o "$DWG_BIN_DIR/dwg2dxf"

if [ ! -x "$DWG_BIN_DIR/dwg2dxf" ]; then
  echo "Failed to build dwg2dxf binary." >&2
  exit 1
fi

mkdir -p "$(dirname "$INSTALL_BIN")"
cp "$DWG_BIN_DIR/dwg2dxf" "$INSTALL_BIN"
chmod +x "$INSTALL_BIN"

echo "dwg2dxf installed to $INSTALL_BIN"
