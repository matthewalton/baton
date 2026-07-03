#!/bin/bash
# Builds Baton in release mode and assembles dist/Baton.app.
set -euo pipefail
cd "$(dirname "$0")/.."

# BATON_SWIFT_FLAGS lets already-sandboxed environments (e.g. the Homebrew
# formula) pass --disable-sandbox — SwiftPM's own sandbox can't nest inside one.
swift build -c release ${BATON_SWIFT_FLAGS:-}

APP=dist/Baton.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp .build/release/BatonApp "$APP/Contents/MacOS/Baton"

ICONSET=$(mktemp -d)/AppIcon.iconset
swift scripts/make-icon.swift "$ICONSET"
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>Baton</string>
    <key>CFBundleDisplayName</key>
    <string>Baton</string>
    <key>CFBundleIdentifier</key>
    <string>com.mattalton.baton</string>
    <key>CFBundleExecutable</key>
    <string>Baton</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSSupportsAutomaticTermination</key>
    <false/>
</dict>
</plist>
PLIST

codesign --force -s - "$APP"
echo "Built $APP"
