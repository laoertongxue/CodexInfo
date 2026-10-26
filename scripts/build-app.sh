#!/usr/bin/env bash
# Builds the menu bar app bundle.
#
# The bundle holds the two release binaries, an Info.plist that makes the app
# an accessory app with the `codexinfo` URL scheme, and an ad-hoc signature.
# The script never touches the Codex configuration.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

APP="$ROOT/dist/CodexInfo.app"

echo "==> Building the panel"
bash "$ROOT/scripts/build-web.sh"

echo "==> Building the release binaries"
swift build -c release --product CodexInfoApp
swift build -c release --product codexinfo-mcp
BIN_DIR="$(swift build -c release --show-bin-path)"

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN_DIR/CodexInfoApp" "$APP/Contents/MacOS/CodexInfoApp"
cp "$BIN_DIR/codexinfo-mcp" "$APP/Contents/MacOS/codexinfo-mcp"
chmod +x "$APP/Contents/MacOS/"*

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>CodexInfoApp</string>
  <key>CFBundleIdentifier</key><string>com.laoer.codexinfo</string>
  <key>CFBundleName</key><string>CodexInfo</string>
  <key>CFBundleDisplayName</key><string>CodexInfo</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.4</string>
  <key>CFBundleVersion</key><string>5</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>CFBundleURLTypes</key>
  <array>
    <dict>
      <key>CFBundleURLName</key><string>com.laoer.codexinfo</string>
      <key>CFBundleURLSchemes</key><array><string>codexinfo</string></array>
    </dict>
  </array>
</dict>
</plist>
PLIST

echo "==> Signing the bundle"
# The helper tool is signed first, so the signature of the bundle covers it.
codesign --force --sign - "$APP/Contents/MacOS/codexinfo-mcp"
codesign --force --deep --sign - "$APP"
codesign --verify --deep "$APP"

echo "Built $APP"
