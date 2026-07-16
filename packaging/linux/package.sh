#!/usr/bin/env bash
set -euo pipefail

# Usage: package.sh <binary_path> <tag> <output_dir> [pack_dir]
#   pack_dir: a full wypas-assets checkout. Mirrors the macOS thin bundle
#   (packaging/macos/package-dmg.sh): bundle ONLY the bootstrap the updater
#   window needs — corelib + updater + its deps + data/ + a rendered
#   updater-ON init.lua — ENC3-encrypted with the binary itself. Everything
#   else (game/client modules, Tibia.dat/.spr, layouts/, mods/) syncs via the
#   updater on first launch.

BINARY_PATH="$1"
TAG="$2"
OUTPUT_DIR="$3"
PACK_DIR="${4:-}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APPDIR="$(mktemp -d)/Wypas.AppDir"
# plaintext init.lua for the seed-gate check — kept OUTSIDE the AppDir so it
# can never be swept into the AppImage.
PLAIN_INIT="$(mktemp)"
trap 'rm -rf "$(dirname "$APPDIR")" "$PLAIN_INIT"' EXIT

echo "==> Creating AppDir structure"
mkdir -p "${APPDIR}/usr/bin"
mkdir -p "${APPDIR}/usr/share/applications"
mkdir -p "${APPDIR}/usr/share/icons/hicolor/256x256/apps"

cp "$BINARY_PATH" "${APPDIR}/usr/bin/wypas"
chmod +x "${APPDIR}/usr/bin/wypas"

# Prod endpoints baked into the bundled init.lua (override via env for staging).
# Services.updater MUST render non-empty so g_app.hasUpdater() is true and the
# client syncs the rest of the pack from /api/updater on first boot.
: "${WYPAS_BASE_URL:=https://wypas.eu}"
: "${WYPAS_DOMAIN:=51.178.242.29}"
: "${WYPAS_PORT:=443}"
: "${WYPAS_SECURE:=true}"

if [ -n "$PACK_DIR" ] && [ -d "$PACK_DIR" ]; then
  # PHYSFS_getBaseDir() resolves to the executable's directory, and the
  # client's work-dir search checks baseDir for init.lua — so the bootstrap
  # pack lives next to the binary inside the (read-only) AppImage mount. The
  # write dir (XDG data home) stays first in the search path and receives the
  # updater-synced files.
  ASSETS_OUT="${APPDIR}/usr/bin"
  echo "==> Bundling THIN bootstrap from $PACK_DIR"
  ( cd "$PACK_DIR" && tar --exclude='.git' --exclude='.github' --exclude='.claude' \
      --exclude='*.md' --exclude='LICENSE' \
      --exclude='.gitattributes' --exclude='.gitignore' -cf - \
      data \
      modules/corelib modules/updater \
      modules/client_locales modules/client_styles modules/client_background \
    ) | tar -xf - -C "$ASSETS_OUT"

  # Render init.lua from the template with prod values (updater ON) — same
  # render as the DMG and the wypas-proxy served pack.
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
  cp "$ASSETS_OUT/init.lua" "$PLAIN_INIT"

  # Encrypt the staged pack in place — the strict release binary rejects
  # plaintext assets outside the write dir, so an unencrypted bundle would
  # brick the boot. --encrypt walks {data,modules,mods,layouts} + init.lua
  # + root Tibia.* under the target dir; the binary sitting in the same dir
  # is not a pack file and is left alone. Bounded: a binary lacking
  # WITH_ENCRYPTION falls through --encrypt into normal startup and would
  # hang CI (no display).
  WYPAS_BIN="${APPDIR}/usr/bin/wypas"
  echo "==> Encrypting pack in place: $WYPAS_BIN --encrypt $ASSETS_OUT"
  "$WYPAS_BIN" --encrypt "$ASSETS_OUT" &
  ENC_PID=$!
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
  if [ "$ENC_RC" -ne 0 ]; then
    echo "ERROR: --encrypt exited non-zero (rc=$ENC_RC)." >&2
    exit 1
  fi
  if [ "$(head -c 4 "$ASSETS_OUT/init.lua" 2>/dev/null)" != "ENC3" ]; then
    echo "ERROR: init.lua is not ENC3-encrypted after --encrypt." >&2
    echo "       wypas-linux must be built WITH_ENCRYPTION with ASSET_ENCRYPTION_SEED set." >&2
    exit 1
  fi
  enc_count=$(find "$ASSETS_OUT/data" "$ASSETS_OUT/modules" \
    -type f 2>/dev/null -exec sh -c '[ "$(head -c 4 "$1" 2>/dev/null)" = ENC3 ]' _ {} \; -print | wc -l | tr -d ' ')
  echo "==> Pack encrypted (${enc_count} ENC3 files bundled)"
  rm -f "$ASSETS_OUT/encryption.log"

  # Seed verification (same check as the DMG): recover the seed from the ENC3
  # adler word of init.lua (known plaintext); reject seed-0 (lenient build,
  # universally decryptable) and wrong-seed (won't match the prod pack).
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
                     "no protection. Build wypas-linux with -DASSET_ENCRYPTION_SEED.\n"); sys.exit(1)
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
else
  echo "ERROR: pack_dir is required — an AppImage without the bootstrap pack cannot boot" >&2
  exit 1
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
