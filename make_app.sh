#!/bin/bash
# 编译并打包成 DiskLens.app,可拖进「应用程序」
set -e
cd "$(dirname "$0")"
swift build -c release
APP=DiskLens.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/DiskLens "$APP/Contents/MacOS/DiskLens"

# 由 Resources/AppIcon.png (1024x1024) 生成 AppIcon.icns
ICONSET="$(mktemp -d)/AppIcon.iconset"
mkdir -p "$ICONSET"
for s in 16 32 128 256 512; do
  sips -z $s $s Resources/AppIcon.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
  sips -z $((s*2)) $((s*2)) Resources/AppIcon.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
# build 号 = git 提交数:每次提交自动 +1,在「关于 DiskLens」里显示为 1.0 (build 号)
BUILD=$(git rev-list --count HEAD 2>/dev/null || echo 0)
cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleExecutable</key><string>DiskLens</string>
  <key>CFBundleIdentifier</key><string>local.disklens</string>
  <key>CFBundleName</key><string>DiskLens</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>$BUILD</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>NSHighResolutionCapable</key><true/>
</dict></plist>
EOF
codesign --force --sign - "$APP"
echo "完成: $(pwd)/$APP  (版本 1.0, build $BUILD)"
