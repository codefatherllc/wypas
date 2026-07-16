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
# plaintext init.lua for the seed-gate check — kept OUTSIDE the staging dir so it can
# never be swept into the DMG (the DMG is built from the whole STAGING_DIR).
PLAIN_INIT="$(mktemp)"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

trap 'rm -rf "$STAGING_DIR" "$PLAIN_INIT"' EXIT

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
# Classic 9.63 login is raw TCP on :7171, which Cloudflare (wypas.eu) does not
# proxy — dial the game server's direct IP until the HTTP login flow lands.
# HTTPS services (updater/status/create-account) still use WYPAS_BASE_URL/Cloudflare.
: "${WYPAS_DOMAIN:=51.178.242.29}"
: "${WYPAS_PORT:=443}"
: "${WYPAS_SECURE:=true}"

# Bundle the full pack under Contents/Resources/ — PHYSFS_getBaseDir() resolves to
# the bundle's Resources dir for a macOS .app, and the client's work-dir search
# checks baseDir for init.lua, so the app runs self-contained.
if [ -n "$PACK_DIR" ] && [ -d "$PACK_DIR" ]; then
  echo "==> Bundling THIN bootstrap from $PACK_DIR"
  ASSETS_OUT="${STAGING_DIR}/${APP_BUNDLE}/Contents/Resources"
  mkdir -p "$ASSETS_OUT"
  # Thin installer: bundle ONLY the bootstrap the updater window needs to run —
  # corelib + updater + its deps (client_locales/styles/background) + data/ (fonts,
  # styles, images the UI renders with). init.lua is rendered below. EVERYTHING else
  # (game/client modules, Tibia.dat/.spr, layouts/, mods/) syncs via the updater on
  # first launch — one auto-restart, then login. Validated: 6.6M bundle → full sync.
  ( cd "$PACK_DIR" && tar --exclude='.git' --exclude='.github' --exclude='.claude' \
      --exclude='*.md' --exclude='LICENSE' \
      --exclude='.gitattributes' --exclude='.gitignore' -cf - \
      data \
      modules/corelib modules/updater \
      modules/client_locales modules/client_styles modules/client_background \
    ) | tar -xf - -C "$ASSETS_OUT"

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
  # Keep the pre-encryption plaintext so the seed check below can recover the seed the
  # binary used (init.lua is encrypted raw — never bytecode-compiled — so its bytes are
  # exactly what the ENC3 adler word was computed over).
  cp "$ASSETS_OUT/init.lua" "$PLAIN_INIT"

  # Encrypt the staged pack in place so the .app ships no readable game assets.
  # The macOS release binary is built WITH_ENCRYPTION and carries the seed, so the
  # same client decrypts transparently at runtime. The tool ENC3-wraps everything it
  # walks ({data,modules,mods,layouts} + init.lua + root Tibia.dat/.spr); the client's
  # exempt extensions are a decrypt-side "plaintext is allowed" list, not an
  # encrypt-side skip. Run from a neutral CWD and pass the dir as the arg (the tool's
  # documented contract) — this is fail-safe: a wrong/old binary that lacks --encrypt
  # support cannot silently mis-encrypt this dir, it just leaves it plaintext, which
  # the ENC3 tripwire below catches.
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

  # Verify on the OUTPUT (enc-engine's recommended ground-truth check), independent
  # of how the binary was built: (1) the tool reported success, and (2) the headline
  # assets are ENC3. init.lua proves the tool ran with its compiled-in seed on this
  # dir; Tibia.dat/.spr are the sprites/dat the deliverable requires unreadable (the
  # tool covers pack-root Tibia.* as of the encryption integration). Fail loudly
  # rather than ship a plaintext .app.
  if [ "$ENC_RC" -ne 0 ]; then
    echo "ERROR: --encrypt exited non-zero (rc=$ENC_RC)." >&2
    exit 1
  fi
  enc_fail=0
  for rel in init.lua Tibia.dat Tibia.spr; do
    f="$ASSETS_OUT/$rel"
    [ -f "$f" ] || continue
    if [ "$(head -c 4 "$f" 2>/dev/null)" != "ENC3" ]; then
      echo "ERROR: $rel is not ENC3-encrypted after --encrypt." >&2
      enc_fail=1
    fi
  done
  if [ "$enc_fail" -ne 0 ]; then
    echo "       The macOS binary must be built WITH_ENCRYPTION (from the integration that" >&2
    echo "       encrypts pack-root Tibia.dat/.spr) with ASSET_ENCRYPTION_SEED set." >&2
    exit 1
  fi
  # Count ENC3 files under the whole bundle (thin bundles omit mods/layouts/Tibia.*,
  # so don't name those dirs — a missing path makes find exit non-zero under pipefail).
  enc_count=$(find "$ASSETS_OUT" \
    -type f 2>/dev/null -exec sh -c '[ "$(head -c 4 "$1" 2>/dev/null)" = ENC3 ]' _ {} \; -print | wc -l | tr -d ' ')
  echo "==> Pack encrypted (${enc_count} ENC3 files bundled)"

  # The --encrypt tool writes its run log (encryption.log) into the pack dir;
  # it is a build artifact, not a client asset — drop it so it is neither
  # bundled in the .app nor listed in the manifest.
  rm -f "$ASSETS_OUT/encryption.log"

  # Seed verification (defense-in-depth at the distribution boundary). The ENC3 adler
  # word (bytes 20-23, LE) is adler32(plaintext) XOR the compiled seed. We know
  # init.lua's plaintext, so recover the seed the binary actually used: a seed-0 pack
  # decrypts on ANY client (zero IP protection — plaintext-equivalent for the deliverable),
  # and a wrong seed won't match the prod-served pack. Reject both. Only runs in CI where
  # the expected seed is supplied; skipped for local/dev builds. No secret is printed.
  if [ -n "${ASSET_ENCRYPTION_SEED:-}" ] && command -v python3 >/dev/null 2>&1; then
    if ! ASSET_ENCRYPTION_SEED="$ASSET_ENCRYPTION_SEED" python3 - \
        "$ASSETS_OUT/init.lua" "$PLAIN_INIT" <<'PY'
import os, sys, zlib, struct
enc, plain = sys.argv[1], sys.argv[2]
with open(enc, 'rb') as f: head = f.read(24)
with open(plain, 'rb') as f: pt = f.read()
if len(head) < 24 or head[:4] != b'ENC3':
    sys.stderr.write("ERROR: init.lua has no ENC3 header for seed check\n"); sys.exit(1)
recovered = struct.unpack('<I', head[20:24])[0] ^ (zlib.adler32(pt) & 0xffffffff)
expected = zlib.adler32(os.environ['ASSET_ENCRYPTION_SEED'].encode()) & 0xffffffff
if recovered == 0:
    sys.stderr.write("ERROR: pack encrypted with seed 0 (lenient) — universally decryptable, "
                     "no protection. Build wypas-macos with -DASSET_ENCRYPTION_SEED.\n"); sys.exit(1)
if recovered != expected:
    sys.stderr.write("ERROR: pack seed %#010x != expected %#010x — binary built with the wrong "
                     "ASSET_ENCRYPTION_SEED.\n" % (recovered, expected)); sys.exit(1)
print("==> Seed verified (binary carries the expected ASSET_ENCRYPTION_SEED)")
PY
    then
      exit 1
    fi
  else
    echo "==> Seed check skipped (ASSET_ENCRYPTION_SEED unset or python3 missing)"
  fi
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

# Create DMG. hdiutil intermittently fails with "Resource busy" on CI runners
# (Spotlight/XProtect still scanning the freshly-staged folder) — retry with a
# delay instead of failing the whole packaging job on a transient.
echo "==> Creating DMG"
mkdir -p "$OUTPUT_DIR"
DMG_PATH="${OUTPUT_DIR}/wypas-setup.dmg"

for attempt in 1 2 3 4 5; do
  if hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$STAGING_DIR" \
    -ov \
    -format UDZO \
    "$DMG_PATH"; then
    break
  fi
  if [ "$attempt" -eq 5 ]; then
    echo "ERROR: hdiutil create failed after $attempt attempts" >&2
    exit 1
  fi
  echo "==> hdiutil create failed (attempt $attempt) — retrying in 10s"
  sleep 10
done

echo "==> Done: ${DMG_PATH}"
