#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release

APP="build/KeyboardSwitcher.app"
# Stable self-signed identity: keeps the macOS Accessibility (TCC) grant valid
# across rebuilds (ad-hoc signatures change cdhash and break the grant every time).
# The identity must exist in the login keychain; override with KS_SIGN_IDENTITY="-"
# for ad-hoc if you don't have it.
SIGN_IDENTITY="${KS_SIGN_IDENTITY:-keyboard-switcher-dev}"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>KeyboardSwitcher</string>
    <key>CFBundleDisplayName</key><string>Keyboard Switcher</string>
    <key>CFBundleIdentifier</key><string>com.travmik.keyboard-switcher</string>
    <key>CFBundleExecutable</key><string>KeyboardSwitcher</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

cp .build/release/KeyboardSwitcher "$APP/Contents/MacOS/KeyboardSwitcher"
codesign --force --sign "$SIGN_IDENTITY" "$APP"
echo "Built $APP"
