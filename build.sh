#!/bin/bash
# Builds Wedge and wraps the executable in a .app bundle.
# Usage:
#   ./build.sh           – debug build into ./build/Wedge.app
#   ./build.sh release   – release build into ./build/Wedge.app
set -euo pipefail

cd "$(dirname "$0")"

CONFIG="${1:-debug}"
APP_NAME="Wedge"
BUNDLE_ID="com.wedge.app"
VERSION="0.1.0"
BUILD_NUMBER="1"

if [ "$CONFIG" = "release" ]; then
    SWIFT_FLAGS="-c release"
    BIN_DIR=".build/release"
else
    SWIFT_FLAGS=""
    BIN_DIR=".build/debug"
fi

echo "==> swift build ($CONFIG)"
swift build $SWIFT_FLAGS

OUTPUT_DIR="build"
APP_PATH="$OUTPUT_DIR/$APP_NAME.app"

rm -rf "$APP_PATH"
mkdir -p "$APP_PATH/Contents/MacOS"
mkdir -p "$APP_PATH/Contents/Resources"

cp "$BIN_DIR/$APP_NAME" "$APP_PATH/Contents/MacOS/$APP_NAME"

# Copy app icon if generated.
ICON_KEY_LINE=""
if [ -f "build/Wedge.icns" ]; then
    cp "build/Wedge.icns" "$APP_PATH/Contents/Resources/Wedge.icns"
    ICON_KEY_LINE='    <key>CFBundleIconFile</key>
    <string>Wedge</string>'
fi

# Copy localizations.
if [ -d "Localizations" ]; then
    for lproj in Localizations/*.lproj; do
        cp -R "$lproj" "$APP_PATH/Contents/Resources/"
    done
fi

cat > "$APP_PATH/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>
    <string>$APP_NAME</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleVersion</key>
    <string>$BUILD_NUMBER</string>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleLocalizations</key>
    <array>
        <string>en</string>
        <string>ru</string>
    </array>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
$ICON_KEY_LINE
    <key>NSHumanReadableCopyright</key>
    <string>Open source. github.com/wwaannttyy/Wedge</string>
</dict>
</plist>
EOF

# Ad-hoc sign so Keychain ACL has a stable identity to bind to.
codesign --force --sign - "$APP_PATH" >/dev/null

echo "==> Built $APP_PATH"
echo "    Run with: open $APP_PATH"
