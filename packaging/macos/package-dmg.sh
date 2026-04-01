#!/usr/bin/env bash
set -euo pipefail

# Usage: package-dmg.sh <binary_path> <tag> <output_dir> [modules_dir]

BINARY_PATH="$1"
TAG="$2"
OUTPUT_DIR="$3"
MODULES_DIR="${4:-}"

APP_NAME="Wypas"
APP_BUNDLE="${APP_NAME}.app"
STAGING_DIR="$(mktemp -d)"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

trap 'rm -rf "$STAGING_DIR"' EXIT

echo "==> Creating .app bundle structure"
mkdir -p "${STAGING_DIR}/${APP_BUNDLE}/Contents/MacOS"
mkdir -p "${STAGING_DIR}/${APP_BUNDLE}/Contents/Resources"
mkdir -p "${STAGING_DIR}/${APP_BUNDLE}/Contents/libs"

cp "$BINARY_PATH" "${STAGING_DIR}/${APP_BUNDLE}/Contents/MacOS/wypas"
chmod +x "${STAGING_DIR}/${APP_BUNDLE}/Contents/MacOS/wypas"

# Bundle updater modules
if [ -n "$MODULES_DIR" ] && [ -d "$MODULES_DIR" ]; then
  echo "==> Bundling modules from $MODULES_DIR"
  mkdir -p "${STAGING_DIR}/${APP_BUNDLE}/Contents/Resources/modules"
  cp -r "$MODULES_DIR"/* "${STAGING_DIR}/${APP_BUNDLE}/Contents/Resources/modules/"
fi

# Info.plist
SHORT_VERSION="${TAG#v}"
cat > "${STAGING_DIR}/${APP_BUNDLE}/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleExecutable</key>
    <string>wypas</string>
    <key>CFBundleIdentifier</key>
    <string>com.wypas.client</string>
    <key>CFBundleVersion</key>
    <string>${SHORT_VERSION}</string>
    <key>CFBundleShortVersionString</key>
    <string>${SHORT_VERSION}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

# .icns from icon.png
ICON_PNG="${SCRIPT_DIR}/../icon.png"
if [ -f "$ICON_PNG" ]; then
  echo "==> Generating AppIcon.icns"
  ICONSET_DIR="${STAGING_DIR}/AppIcon.iconset"
  mkdir -p "$ICONSET_DIR"
  for size in 16 32 64 128 256 512 1024; do
    sips -z $size $size "$ICON_PNG" --out "${ICONSET_DIR}/icon_${size}x${size}.png" 2>/dev/null
  done
  # @2x variants
  sips -z 32 32   "$ICON_PNG" --out "${ICONSET_DIR}/icon_16x16@2x.png"   2>/dev/null
  sips -z 64 64   "$ICON_PNG" --out "${ICONSET_DIR}/icon_32x32@2x.png"   2>/dev/null
  sips -z 256 256 "$ICON_PNG" --out "${ICONSET_DIR}/icon_128x128@2x.png" 2>/dev/null
  sips -z 512 512 "$ICON_PNG" --out "${ICONSET_DIR}/icon_256x256@2x.png" 2>/dev/null
  sips -z 1024 1024 "$ICON_PNG" --out "${ICONSET_DIR}/icon_512x512@2x.png" 2>/dev/null
  iconutil -c icns "$ICONSET_DIR" -o "${STAGING_DIR}/${APP_BUNDLE}/Contents/Resources/AppIcon.icns"
  rm -rf "$ICONSET_DIR"
fi

# Bundle dylibs
echo "==> Running dylibbundler"
dylibbundler \
  -od \
  -b \
  -x "${STAGING_DIR}/${APP_BUNDLE}/Contents/MacOS/wypas" \
  -d "${STAGING_DIR}/${APP_BUNDLE}/Contents/libs/" \
  -p @executable_path/../libs/ \
  2>&1 || echo "==> dylibbundler completed (some libs may be static)"

# Applications symlink for drag-and-drop install
ln -s /Applications "${STAGING_DIR}/Applications"

# Create DMG
echo "==> Creating DMG"
mkdir -p "$OUTPUT_DIR"
DMG_PATH="${OUTPUT_DIR}/wypas-setup.dmg"

hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$STAGING_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

echo "==> Done: ${DMG_PATH}"
