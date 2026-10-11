#!/bin/sh
# Builds build/Xportcap.app (release, ad-hoc signed).
set -e
cd "$(dirname "$0")"
swift build -c release
APP=build/Xportcap.app
rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS"
cp .build/release/Xportcap "$APP/Contents/MacOS/"
# app icon, rendered from LogoView
mkdir -p "$APP/Contents/Resources" build/AppIcon.iconset
.build/release/Xportcap --render-icon build/icon.png
for s in 16 32 128 256 512; do
  sips -z $s $s build/icon.png --out build/AppIcon.iconset/icon_${s}x${s}.png >/dev/null
  sips -z $((s*2)) $((s*2)) build/icon.png --out build/AppIcon.iconset/icon_${s}x${s}@2x.png >/dev/null
done
iconutil -c icns build/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleExecutable</key><string>Xportcap</string>
  <key>CFBundleIdentifier</key><string>app.xportcap</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleName</key><string>Xportcap</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>LSMinimumSystemVersion</key><string>15.0</string>
  <key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign -s - --force "$APP"
echo "Built $APP"
