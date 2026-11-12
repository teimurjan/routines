#!/bin/sh
# Builds build/Routines.app: the release binary, its resources, the app icon, the workspace source and the routines:// URL scheme.
set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
APP="$ROOT/build/Routines.app"
VERSION=$(date +%Y.%m.%d)

cd "$ROOT/app"
swift build -c release
BIN=$(swift build -c release --show-bin-path)

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/Routines" "$APP/Contents/MacOS/Routines"
cp -R "$BIN/Routines_RoutinesKit.bundle" "$BIN/Routines_Routines.bundle" "$APP/Contents/Resources/"
cp "$ROOT/logo/icon/macos/AppIcon.icns" "$APP/Contents/Resources/"

# The workspace of the threads. cp -R keeps the links of its node_modules.
cp -R "$ROOT/build/workspace" "$APP/Contents/Resources/workspace"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Routines</string>
  <key>CFBundleDisplayName</key><string>Routines</string>
  <key>CFBundleIdentifier</key><string>dev.teimurjan.routines</string>
  <key>CFBundleExecutable</key><string>Routines</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>LSMinimumSystemVersion</key><string>15.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>CFBundleURLTypes</key>
  <array>
    <dict>
      <key>CFBundleURLName</key><string>dev.teimurjan.routines</string>
      <key>CFBundleURLSchemes</key><array><string>routines</string></array>
    </dict>
  </array>
</dict>
</plist>
PLIST

# An ad hoc signature is enough for notifications and the login item on this Mac.
codesign --force --deep --sign - "$APP"
echo "built $APP"
