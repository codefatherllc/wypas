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

STAGING_DIR="$(mktemp -d)"
trap 'rm -rf "$STAGING_DIR"' EXIT

echo "==> Creating package structure"
mkdir -p "${STAGING_DIR}/wypas/assets"

# Copy binary
cp "$BINARY_PATH" "${STAGING_DIR}/wypas/wypas"
chmod +x "${STAGING_DIR}/wypas/wypas"

# Copy assets (excluding repo metadata)
echo "==> Copying assets"
rsync -a \
  --exclude='.git/' \
  --exclude='.github/' \
  --exclude='manifest.json' \
  --exclude='.gitattributes' \
  --exclude='.gitignore' \
  "${ASSETS_DIR}/" "${STAGING_DIR}/wypas/assets/"

# Create tar.gz
echo "==> Creating tar.gz"
mkdir -p "$OUTPUT_DIR"
tar -czf "${OUTPUT_DIR}/wypas-linux.tar.gz" -C "$STAGING_DIR" wypas

echo "==> Done: ${OUTPUT_DIR}/wypas-linux.tar.gz"
