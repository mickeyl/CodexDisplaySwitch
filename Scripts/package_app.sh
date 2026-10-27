#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

swift build -c release
BIN_DIR=$(swift build -c release --show-bin-path)
APP="$ROOT/build/Codex Display Switch.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/CodexDisplaySwitch" "$APP/Contents/MacOS/"
cp "$BIN_DIR/codex-displays" "$APP/Contents/MacOS/"
cp -R "$BIN_DIR/CodexDisplaySwitch_CodexDisplaySwitch.bundle" "$APP/Contents/Resources/"
cp "$ROOT/Assets/AppIcon.icns" "$APP/Contents/Resources/"
cp "$ROOT/LICENSE" "$APP/Contents/Resources/"
cp -R "$ROOT/ThirdPartyLicenses" "$APP/Contents/Resources/"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>io.github.mickeyl.CodexDisplaySwitch</string>
    <key>CFBundleName</key><string>Codex Display Switch</string>
    <key>CFBundleDisplayName</key><string>Codex Display Switch</string>
    <key>CFBundleExecutable</key><string>CodexDisplaySwitch</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>CFBundleIconFile</key><string>AppIcon</string>
</dict>
</plist>
PLIST

chmod -R u+w "$APP"
xattr -cr "$APP"
codesign --force --sign - "$APP/Contents/MacOS/codex-displays"
codesign --force --sign - "$APP"
codesign --verify --deep --strict "$APP"
echo "Created $APP"
