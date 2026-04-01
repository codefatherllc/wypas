#!/usr/bin/env bash
set -euo pipefail

# Usage: package.sh <binary_path> <tag> <output_dir> [modules_dir]

BINARY_PATH="$1"
TAG="$2"
OUTPUT_DIR="$3"
MODULES_DIR="${4:-}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APPDIR="$(mktemp -d)/Wypas.AppDir"
trap 'rm -rf "$(dirname "$APPDIR")"' EXIT

echo "==> Creating AppDir structure"
mkdir -p "${APPDIR}/usr/bin"
mkdir -p "${APPDIR}/usr/share/applications"
mkdir -p "${APPDIR}/usr/share/icons/hicolor/256x256/apps"

cp "$BINARY_PATH" "${APPDIR}/usr/bin/wypas"
chmod +x "${APPDIR}/usr/bin/wypas"

# Bundle updater modules
if [ -n "$MODULES_DIR" ] && [ -d "$MODULES_DIR" ]; then
  echo "==> Bundling modules from $MODULES_DIR"
  mkdir -p "${APPDIR}/usr/bin/modules"
  cp -r "$MODULES_DIR"/* "${APPDIR}/usr/bin/modules/"
fi

# Icon
ICON_SRC="${SCRIPT_DIR}/../icon.png"
if [ -f "$ICON_SRC" ]; then
  cp "$ICON_SRC" "${APPDIR}/usr/share/icons/hicolor/256x256/apps/wypas.png"
  cp "$ICON_SRC" "${APPDIR}/wypas.png"
fi

# Desktop entry
cat > "${APPDIR}/wypas.desktop" <<DESKTOP
[Desktop Entry]
Type=Application
Name=Wypas
Exec=wypas
Icon=wypas
Categories=Game;
DESKTOP
cp "${APPDIR}/wypas.desktop" "${APPDIR}/usr/share/applications/"

# AppRun
cat > "${APPDIR}/AppRun" <<'APPRUN'
#!/bin/bash
HERE="$(dirname "$(readlink -f "$0")")"
export LD_LIBRARY_PATH="${HERE}/usr/lib:${LD_LIBRARY_PATH:-}"
exec "${HERE}/usr/bin/wypas" "$@"
APPRUN
chmod +x "${APPDIR}/AppRun"

echo "==> Creating AppImage"
mkdir -p "$OUTPUT_DIR"
ARCH=x86_64 appimagetool "$APPDIR" "${OUTPUT_DIR}/wypas.AppImage"

echo "==> Done: ${OUTPUT_DIR}/wypas.AppImage"
