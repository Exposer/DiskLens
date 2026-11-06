#!/bin/bash
# 编译并打包成 DiskLens.app,可拖进「应用程序」
set -e
cd "$(dirname "$0")"
swift build -c release
APP=DiskLens.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/DiskLens "$APP/Contents/MacOS/DiskLens"
cat > "$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleExecutable</key><string>DiskLens</string>
  <key>CFBundleIdentifier</key><string>local.disklens</string>
  <key>CFBundleName</key><string>DiskLens</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>NSHighResolutionCapable</key><true/>
</dict></plist>
EOF
codesign --force --sign - "$APP"
echo "完成: $(pwd)/$APP"
