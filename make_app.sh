#!/bin/bash
# 编译并打包成 DiskLens.app,可拖进「应用程序」
set -e
cd "$(dirname "$0")"
# 编译产物放在 iCloud 同步范围之外:项目在 Documents 里时,.build 里成千上万个文件被同步会让编译慢到卡住
BUILD_DIR="${DISKLENS_BUILD_DIR:-$HOME/Library/Caches/disklens-build}"
swift build -c release --scratch-path "$BUILD_DIR"
# 先在临时目录里组装并签名:项目放在 Documents / iCloud 里时,File Provider 会给 .app 目录加上
# 清不掉的扩展属性,导致 codesign 报 "detritus not allowed"。签完再拷回项目目录。
OUT=DiskLens.app
STAGE="$(mktemp -d)"
APP="$STAGE/DiskLens.app"
rm -rf "$OUT"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BUILD_DIR/release/DiskLens" "$APP/Contents/MacOS/DiskLens"

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
xattr -cr "$APP"
# 签名:默认是临时(ad-hoc)签名,但这样每次打包的“指定要求”都是这一份二进制的哈希,
# 系统会把新包当成另一个程序,之前授予的「完全磁盘访问权限」就失效了(扫描会少算受保护的目录)。
# 想让权限只授予一次:用固定证书签名,例如
#   DISKLENS_SIGN_IDENTITY="Apple Development: 你的名字 (TEAMID)" ./make_app.sh
# 可用的证书见 `security find-identity -v -p codesigning`
SIGN_ID="${DISKLENS_SIGN_IDENTITY:--}"
codesign --force --sign "$SIGN_ID" "$APP"
if [ "$SIGN_ID" = "-" ]; then
  echo "提示: 使用的是临时签名,每次重新打包后都需要重新授予「完全磁盘访问权限」。设置 DISKLENS_SIGN_IDENTITY 可避免。"
fi
ditto --norsrc --noextattr "$APP" "$OUT"
rm -rf "$STAGE"
echo "完成: $(pwd)/$OUT  (版本 1.0, build $BUILD)"
