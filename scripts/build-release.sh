#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="AudioFormatBar"
VERSION="${1:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT_DIR/Resources/Info.plist")}"
BUILD_ROOT="$ROOT_DIR/.build-release"
ARM_BUILD="$BUILD_ROOT/arm64"
INTEL_BUILD="$BUILD_ROOT/x86_64"
OUTPUT_DIR="$ROOT_DIR/dist/releases"
APP_DIR="$OUTPUT_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
UNIVERSAL_BINARY="$BUILD_ROOT/$APP_NAME-universal"

cd "$ROOT_DIR"

swift build \
    -c release \
    --product "$APP_NAME" \
    --triple arm64-apple-macosx26.0 \
    --scratch-path "$ARM_BUILD"

swift build \
    -c release \
    --product "$APP_NAME" \
    --triple x86_64-apple-macosx26.0 \
    --scratch-path "$INTEL_BUILD"

mkdir -p "$BUILD_ROOT" "$OUTPUT_DIR"
lipo -create \
    "$ARM_BUILD/release/$APP_NAME" \
    "$INTEL_BUILD/release/$APP_NAME" \
    -output "$UNIVERSAL_BINARY"

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
cp "$UNIVERSAL_BINARY" "$MACOS_DIR/$APP_NAME"
cp "$ROOT_DIR/Resources/Info.plist" "$CONTENTS_DIR/Info.plist"

codesign --force --deep --sign - "$APP_DIR" >/dev/null

ZIP_NAME="$APP_NAME-v$VERSION-macOS-universal.zip"
DMG_NAME="$APP_NAME-v$VERSION-macOS-universal.dmg"
CHECKSUM_NAME="SHA256SUMS.txt"

ditto \
    -c -k --sequesterRsrc --keepParent \
    "$APP_DIR" \
    "$OUTPUT_DIR/$ZIP_NAME"

hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$APP_DIR" \
    -ov \
    -format UDZO \
    "$OUTPUT_DIR/$DMG_NAME" >/dev/null

(
    cd "$OUTPUT_DIR"
    shasum -a 256 "$ZIP_NAME" "$DMG_NAME" > "$CHECKSUM_NAME"
)

echo "Release artifacts:"
echo "  $OUTPUT_DIR/$ZIP_NAME"
echo "  $OUTPUT_DIR/$DMG_NAME"
echo "  $OUTPUT_DIR/$CHECKSUM_NAME"
