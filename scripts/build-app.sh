#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_NAME="TokenWorth"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
VERSION="${VERSION:-0.1.0}"
ARCHIVE=0

for arg in "$@"; do
  case "$arg" in
    --archive) ARCHIVE=1 ;;
    *)
      echo "Unknown option: $arg" >&2
      exit 1
      ;;
  esac
done

cd "$ROOT_DIR"

echo "Building release binaries..."
swift build -c release

BIN_DIR="$(swift build -c release --show-bin-path)"
APP_BIN="$BIN_DIR/TokenWorth"
CLI_BIN="$BIN_DIR/tokenworth-cli"

if [[ ! -x "$APP_BIN" || ! -x "$CLI_BIN" ]]; then
  echo "Expected release binaries not found in $BIN_DIR" >&2
  exit 1
fi

rm -rf "$APP_BUNDLE" "$DIST_DIR/tokenworth"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"

cp "$APP_BIN" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
cp "$CLI_BIN" "$DIST_DIR/tokenworth"
chmod +x "$APP_BUNDLE/Contents/MacOS/$APP_NAME" "$DIST_DIR/tokenworth"

cat > "$APP_BUNDLE/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleDisplayName</key>
    <string>TokenWorth</string>
    <key>CFBundleExecutable</key>
    <string>TokenWorth</string>
    <key>CFBundleIdentifier</key>
    <string>io.github.alexkris.tokenworth</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>TokenWorth</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

echo "Ad-hoc signing $APP_BUNDLE..."
codesign --force --deep --sign - "$APP_BUNDLE"

if [[ "$ARCHIVE" -eq 1 ]]; then
  ARCH="$(uname -m)"
  echo "Creating release archives for $ARCH..."
  rm -f "$DIST_DIR/TokenWorth-macos-${ARCH}.zip" "$DIST_DIR/tokenworth-cli-macos-${ARCH}.tar.gz"
  ditto -c -k --sequesterRsrc --keepParent "$APP_BUNDLE" "$DIST_DIR/TokenWorth-macos-${ARCH}.zip"
  tar -czf "$DIST_DIR/tokenworth-cli-macos-${ARCH}.tar.gz" -C "$DIST_DIR" tokenworth
fi

echo "Done:"
echo "  App Bundle: $APP_BUNDLE"
echo "  CLI Binary: $DIST_DIR/tokenworth"
