#!/bin/sh
# Builds a release DiskTree.app in the repo root.
set -e
cd "$(dirname "$0")/.."
swift build -c release
APP=DiskTree.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/DiskTree "$APP/Contents/MacOS/"
# Assets.car for macOS 26+ (no grey icon tile), AppIcon.icns for older systems.
xcrun actool assets/AppIcon.icon --compile "$APP/Contents/Resources" --platform macosx \
  --minimum-deployment-target 14.0 --app-icon AppIcon --output-partial-info-plist /dev/null >/dev/null
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>DiskTree</string>
  <key>CFBundleIdentifier</key><string>com.chuyeow.disktree</string>
  <key>CFBundleExecutable</key><string>DiskTree</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleIconName</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$APP"
echo "built $APP"
