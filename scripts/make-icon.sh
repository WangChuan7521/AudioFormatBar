#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE_IMAGE="${1:-$ROOT_DIR/图标.jpeg}"
ICONSET_DIR="$ROOT_DIR/.build-release/AppIcon.iconset"
OUTPUT_ICNS="$ROOT_DIR/Resources/AppIcon.icns"

if [[ ! -f "$SOURCE_IMAGE" ]]; then
    echo "Icon source not found: $SOURCE_IMAGE" >&2
    exit 1
fi

rm -rf "$ICONSET_DIR"
swift "$ROOT_DIR/scripts/make-icon.swift" "$SOURCE_IMAGE" "$ICONSET_DIR"
iconutil -c icns "$ICONSET_DIR" -o "$OUTPUT_ICNS"

echo "Generated: $OUTPUT_ICNS"
