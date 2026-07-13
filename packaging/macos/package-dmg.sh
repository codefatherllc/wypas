#!/usr/bin/env bash
set -euo pipefail

# Usage: package-dmg.sh <binary_path> <tag> <output_dir> [pack_dir]
#   pack_dir: a full wypas-assets checkout — its init.lua, data/, modules/, mods/,
#   layouts/ and Tibia.dat/.spr are bundled so the app is self-contained.

BINARY_PATH="$1"
TAG="$2"
OUTPUT_DIR="$3"
PACK_DIR="${4:-}"

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

# Prod endpoints baked into the bundled init.lua (override via env for staging).
# These MUST render Services.updater non-empty so g_app.hasUpdater() is true and
# the shipped client self-updates per-file from /api/updater — no re-bundle needed.
: "${WYPAS_BASE_URL:=https://wypas.eu}"
: "${WYPAS_DOMAIN:=wypas.eu}"
: "${WYPAS_PORT:=443}"
: "${WYPAS_SECURE:=true}"

# Bundle the full pack under Contents/Resources/ — PHYSFS_getBaseDir() resolves to
# the bundle's Resources dir for a macOS .app, and the client's work-dir search
# checks baseDir for init.lua, so the app runs self-contained.
if [ -n "$PACK_DIR" ] && [ -d "$PACK_DIR" ]; then
  echo "==> Bundling pack from $PACK_DIR"
  ASSETS_OUT="${STAGING_DIR}/${APP_BUNDLE}/Contents/Resources"
  mkdir -p "$ASSETS_OUT"
  # exclude repo/dev cruft and the template; init.lua is rendered below, not copied
  ( cd "$PACK_DIR" && tar --exclude='.git' --exclude='.github' --exclude='.claude' \
      --exclude='*.md' --exclude='LICENSE' --exclude='init.lua.tmpl' --exclude='init.lua' \
      --exclude='.gitattributes' --exclude='.gitignore' -cf - . ) | tar -xf - -C "$ASSETS_OUT"

  # Render init.lua from the template with prod values so the auto-updater is ON.
  # Mirrors wypas-proxy/Makefile's prod render; kept here so the offline .app bundle
  # gets the same updater-enabled init.lua that prod serves to the Windows client.
  TMPL="$PACK_DIR/init.lua.tmpl"
  if [ ! -f "$TMPL" ]; then
    echo "ERROR: init.lua.tmpl missing from pack ($TMPL)" >&2
    exit 1
  fi
  sed -e "s|__BASE_URL__|${WYPAS_BASE_URL}|g" \
      -e "s|__DOMAIN__|${WYPAS_DOMAIN}|g" \
      -e "s|__PORT__|${WYPAS_PORT}|g" \
      -e "s|__SECURE__|${WYPAS_SECURE}|g" \
      "$TMPL" > "$ASSETS_OUT/init.lua"
  if ! grep -q "${WYPAS_BASE_URL}/api/updater" "$ASSETS_OUT/init.lua"; then
    echo "ERROR: rendered init.lua does not point Services.updater at prod" >&2
    exit 1
  fi
  echo "==> Rendered init.lua (updater -> ${WYPAS_BASE_URL}/api/updater)"

  # Encrypt the staged pack in place so the .app ships no readable game assets.
  # The macOS release binary is built WITH_ENCRYPTION and carries the seed, so the
  # same client decrypts transparently at runtime; exempt files (.otml, ...) are
  # left plaintext by the tool. Run from a neutral CWD and pass the dir as the arg
  # (the tool's documented contract) — this is fail-safe: a wrong/old binary that
  # lacks --encrypt support cannot silently mis-encrypt this dir, it just leaves it
  # plaintext, which the ENC3 tripwire below catches.
  WYPAS_BIN="${STAGING_DIR}/${APP_BUNDLE}/Contents/MacOS/wypas"
  echo "==> Encrypting pack in place: $WYPAS_BIN --encrypt $ASSETS_OUT"
  "$WYPAS_BIN" --encrypt "$ASSETS_OUT" &
  ENC_PID=$!
  # Bound the run: a binary lacking WITH_ENCRYPTION falls through --encrypt into
  # normal startup and would otherwise hang CI (no display). Poll for exit so no
  # stray background timer lingers holding the job's stdout open.
  ENC_TIMEOUT="${WYPAS_ENCRYPT_TIMEOUT:-180}"
  waited=0
  while kill -0 "$ENC_PID" 2>/dev/null; do
    if [ "$waited" -ge "$ENC_TIMEOUT" ]; then
      echo "ERROR: --encrypt exceeded ${ENC_TIMEOUT}s; killing (binary likely lacks WITH_ENCRYPTION)" >&2
      kill -9 "$ENC_PID" 2>/dev/null || true
      break
    fi
    sleep 2
    waited=$((waited + 2))
  done
  ENC_RC=0
  wait "$ENC_PID" 2>/dev/null || ENC_RC=$?

  # Tripwire: init.lua MUST be ENC3 after --encrypt. This is the reliable proof the
  # tool ran with its compiled-in seed on this dir; a binary lacking WITH_ENCRYPTION
  # (or a wrong dir/seed) leaves it plaintext. Fail loudly rather than ship plaintext.
  if [ "$(head -c 4 "$ASSETS_OUT/init.lua" 2>/dev/null)" != "ENC3" ]; then
    echo "ERROR: init.lua is not ENC3-encrypted after --encrypt (rc=$ENC_RC)." >&2
    echo "       The macOS binary must be built WITH_ENCRYPTION with ASSET_ENCRYPTION_SEED set." >&2
    exit 1
  fi
  enc_count=$(find "$ASSETS_OUT/data" "$ASSETS_OUT/modules" "$ASSETS_OUT/mods" "$ASSETS_OUT/layouts" \
    -type f 2>/dev/null -exec sh -c '[ "$(head -c 4 "$1" 2>/dev/null)" = ENC3 ]' _ {} \; -print | wc -l | tr -d ' ')
  echo "==> Pack encrypted (init.lua ENC3; ${enc_count} files under data/modules/mods/layouts ENC3)"
  # The client's --encrypt covers data/modules/mods/layouts + init.lua but NOT the
  # pack-root Tibia.dat/.spr (they sit outside those dirs), so the sprites/dat still
  # ship readable. Warn loudly — closing this needs the client's encrypt tool to
  # cover pack-root assets; it cannot be done from packaging.
  for rel in Tibia.dat Tibia.spr; do
    f="$ASSETS_OUT/$rel"
    [ -f "$f" ] || continue
    if [ "$(head -c 4 "$f" 2>/dev/null)" != "ENC3" ]; then
      echo "WARNING: $rel is NOT encrypted — pack-root sprites/dat are outside --encrypt scope." >&2
    fi
  done
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
