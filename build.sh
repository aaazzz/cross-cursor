#!/bin/bash
# CrossCursor.app をビルドする。 ./build.sh install で /Applications にコピーして起動。
set -euo pipefail
cd "$(dirname "$0")"

APP=build/CrossCursor.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"

swiftc -O -swift-version 5 \
  -target "$(uname -m)-apple-macosx14.0" \
  -o "$APP/Contents/MacOS/CrossCursor" \
  Sources/main.swift

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>CrossCursor</string>
  <key>CFBundleIdentifier</key><string>local.crosscursor</string>
  <key>CFBundleExecutable</key><string>CrossCursor</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

# 署名の要件を bundle ID に固定し、作り直しても入力監視の許可が外れないようにする
codesign --force --sign - -r='designated => identifier "local.crosscursor"' "$APP"
echo "Built: $APP"

if [[ "${1:-}" == "install" ]]; then
  pkill -x CrossCursor || true
  rm -rf /Applications/CrossCursor.app
  cp -R "$APP" /Applications/
  open /Applications/CrossCursor.app
  echo "Installed: /Applications/CrossCursor.app"
fi
