#!/usr/bin/env bash
set -euo pipefail

# Usage: package-dmg.sh <binary_path> <assets_dir> <tag> <output_dir>

if [ $# -ne 4 ]; then
  echo "Usage: $0 <binary_path> <assets_dir> <tag> <output_dir>"
  exit 1
fi

BINARY_PATH="$1"
ASSETS_DIR="$2"
TAG="$3"
OUTPUT_DIR="$4"

APP_NAME="Wypas"
APP_BUNDLE="${APP_NAME}.app"
STAGING_DIR="$(mktemp -d)"

trap 'rm -rf "$STAGING_DIR"' EXIT

echo "==> Creating .app bundle structure"
mkdir -p "${STAGING_DIR}/${APP_BUNDLE}/Contents/MacOS"
mkdir -p "${STAGING_DIR}/${APP_BUNDLE}/Contents/Resources"
mkdir -p "${STAGING_DIR}/${APP_BUNDLE}/Contents/libs"

# Copy binary
cp "$BINARY_PATH" "${STAGING_DIR}/${APP_BUNDLE}/Contents/MacOS/wypas"
chmod +x "${STAGING_DIR}/${APP_BUNDLE}/Contents/MacOS/wypas"

# Copy assets (excluding repo metadata)
echo "==> Copying assets"
rsync -a \
  --exclude='.git/' \
  --exclude='.github/' \
  --exclude='manifest.json' \
  --exclude='.gitattributes' \
  --exclude='.gitignore' \
  "${ASSETS_DIR}/" "${STAGING_DIR}/${APP_BUNDLE}/Contents/MacOS/assets/"

# Generate Info.plist
SHORT_VERSION="${TAG#v}"  # strip leading 'v'
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

# Generate .icns from icon.png if it exists
ICON_PNG="${ASSETS_DIR}/data/images/icon.png"
if [ -f "$ICON_PNG" ]; then
  echo "==> Generating AppIcon.icns from icon.png"
  ICONSET_DIR="${STAGING_DIR}/AppIcon.iconset"
  mkdir -p "$ICONSET_DIR"
  sips -z 16 16     "$ICON_PNG" --out "${ICONSET_DIR}/icon_16x16.png"      2>/dev/null
  sips -z 32 32     "$ICON_PNG" --out "${ICONSET_DIR}/icon_16x16@2x.png"   2>/dev/null
  sips -z 32 32     "$ICON_PNG" --out "${ICONSET_DIR}/icon_32x32.png"      2>/dev/null
  sips -z 64 64     "$ICON_PNG" --out "${ICONSET_DIR}/icon_32x32@2x.png"   2>/dev/null
  sips -z 128 128   "$ICON_PNG" --out "${ICONSET_DIR}/icon_128x128.png"    2>/dev/null
  sips -z 256 256   "$ICON_PNG" --out "${ICONSET_DIR}/icon_128x128@2x.png" 2>/dev/null
  sips -z 256 256   "$ICON_PNG" --out "${ICONSET_DIR}/icon_256x256.png"    2>/dev/null
  sips -z 512 512   "$ICON_PNG" --out "${ICONSET_DIR}/icon_256x256@2x.png" 2>/dev/null
  sips -z 512 512   "$ICON_PNG" --out "${ICONSET_DIR}/icon_512x512.png"    2>/dev/null
  sips -z 1024 1024 "$ICON_PNG" --out "${ICONSET_DIR}/icon_512x512@2x.png" 2>/dev/null
  iconutil -c icns "$ICONSET_DIR" -o "${STAGING_DIR}/${APP_BUNDLE}/Contents/Resources/AppIcon.icns"
  rm -rf "$ICONSET_DIR"
else
  echo "==> No icon.png found at ${ICON_PNG}, skipping .icns generation"
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

# Create DMG
echo "==> Creating DMG"
mkdir -p "$OUTPUT_DIR"
DMG_PATH="${OUTPUT_DIR}/wypas-macos.dmg"

hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$STAGING_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

echo "==> Done: ${DMG_PATH}"
