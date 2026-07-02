#!/bin/bash
# Builds Deck in release mode and assembles dist/Deck.app.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release

APP=dist/Deck.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp .build/release/DeckApp "$APP/Contents/MacOS/Deck"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>Deck</string>
    <key>CFBundleDisplayName</key>
    <string>Deck</string>
    <key>CFBundleIdentifier</key>
    <string>com.mattalton.deck</string>
    <key>CFBundleExecutable</key>
    <string>Deck</string>
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
