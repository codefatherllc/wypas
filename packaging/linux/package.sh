#!/usr/bin/env bash
set -euo pipefail

# Usage: package.sh <binary_path> <assets_dir> <tag> <output_dir>

if [ $# -ne 4 ]; then
  echo "Usage: $0 <binary_path> <assets_dir> <tag> <output_dir>"
  exit 1
fi

BINARY_PATH="$1"
ASSETS_DIR="$2"
TAG="$3"
OUTPUT_DIR="$4"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APPDIR="$(mktemp -d)/Wypas.AppDir"
trap 'rm -rf "$(dirname "$APPDIR")"' EXIT

echo "==> Creating AppDir structure"
mkdir -p "${APPDIR}/usr/bin"
mkdir -p "${APPDIR}/usr/share/applications"
mkdir -p "${APPDIR}/usr/share/icons/hicolor/256x256/apps"

# Copy binary
cp "$BINARY_PATH" "${APPDIR}/usr/bin/wypas"
chmod +x "${APPDIR}/usr/bin/wypas"

# Copy assets
echo "==> Copying assets"
mkdir -p "${APPDIR}/usr/bin/assets"
rsync -a \
  --exclude='.git/' \
  --exclude='.github/' \
  --exclude='manifest.json' \
  --exclude='.gitattributes' \
  --exclude='.gitignore' \
  "${ASSETS_DIR}/" "${APPDIR}/usr/bin/assets/"

# Icon — use icon.png from assets if available, otherwise generate from .ico
ICON_SRC="${ASSETS_DIR}/data/images/clienticon.png"
if [ -f "$ICON_SRC" ]; then
  cp "$ICON_SRC" "${APPDIR}/usr/share/icons/hicolor/256x256/apps/wypas.png"
  cp "$ICON_SRC" "${APPDIR}/wypas.png"
else
  echo "==> Warning: no icon found at ${ICON_SRC}"
  # Create a placeholder 1x1 PNG
  printf '\x89PNG\r\n\x1a\n' > "${APPDIR}/wypas.png"
fi

# Desktop entry
cat > "${APPDIR}/usr/share/applications/wypas.desktop" <<DESKTOP
[Desktop Entry]
Type=Application
Name=Wypas
Exec=wypas
Icon=wypas
Categories=Game;
DESKTOP
cp "${APPDIR}/usr/share/applications/wypas.desktop" "${APPDIR}/wypas.desktop"

# AppRun
cat > "${APPDIR}/AppRun" <<'APPRUN'
#!/bin/bash
HERE="$(dirname "$(readlink -f "$0")")"
export LD_LIBRARY_PATH="${HERE}/usr/lib:${LD_LIBRARY_PATH:-}"
exec "${HERE}/usr/bin/wypas" "$@"
APPRUN
chmod +x "${APPDIR}/AppRun"

# Download appimagetool if not present
APPIMAGETOOL="/tmp/appimagetool"
if [ ! -x "$APPIMAGETOOL" ]; then
  echo "==> Downloading appimagetool"
  curl -fsSL -o "$APPIMAGETOOL" \
    "https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-x86_64.AppImage"
  chmod +x "$APPIMAGETOOL"
fi

# Build AppImage
echo "==> Creating AppImage"
mkdir -p "$OUTPUT_DIR"
ARCH=x86_64 "$APPIMAGETOOL" "$APPDIR" "${OUTPUT_DIR}/wypas-linux.AppImage"

echo "==> Done: ${OUTPUT_DIR}/wypas-linux.AppImage"
