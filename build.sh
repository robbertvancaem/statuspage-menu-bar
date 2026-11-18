#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="Statuspage Menu Bar"
BUNDLE_ID="com.robbertvancaem.statuspage-menu-bar"
APP_DIR="/Applications/${APP_NAME}.app"
VERSION="0.2.0"

echo "Building..."
cd "$SCRIPT_DIR"
# Universal binary: build each arch separately (multi --arch needs full Xcode) and merge.
BINARIES=""
for ARCH in arm64 x86_64; do
    swift build -c release --triple "${ARCH}-apple-macosx14.0" 2>&1
    BINARIES="$BINARIES $(swift build -c release --triple "${ARCH}-apple-macosx14.0" --show-bin-path)/StatuspageMenuBar"
done
BINARY="$SCRIPT_DIR/.build/StatuspageMenuBar-universal"
lipo -create $BINARIES -output "$BINARY"

echo "Writing app bundle..."
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

cat > "$APP_DIR/Contents/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>StatuspageMenuBar</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleVersion</key>
    <string>${VERSION}</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
</dict>
</plist>
PLIST

cp "$BINARY" "$APP_DIR/Contents/MacOS/StatuspageMenuBar"

echo "Re-signing bundle..."
codesign --force --sign - "$APP_DIR"

echo "Done! App at: $APP_DIR"
echo "Run: open '$APP_DIR'"
