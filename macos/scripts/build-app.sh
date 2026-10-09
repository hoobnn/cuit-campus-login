#!/bin/bash
# 构建并签名 build/CUITNet.app（arm64 + x86_64 通用二进制）。
#
# 用法：scripts/build-app.sh [版本号] [构建号]
#
# 设置了 SIGN_IDENTITY（如 "Developer ID Application: 姓名 (TEAMID)"）时，
# 用 Developer ID 签名并启用 Hardened Runtime 与安全时间戳，可以拿去公证；
# 否则做 ad-hoc 签名，只适合本机调试。完整发布流程见 scripts/release.sh。
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:-0.1.0}"
BUILD="${2:-1}"
OUT=build
APP="$OUT/CUITNet.app"
rm -rf "$OUT" && mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

swift build -c release --arch arm64 --arch x86_64
cp "$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/CUITNet" "$APP/Contents/MacOS/CUITNet"

# 图标由 assets/icon/build.sh 从 SVG 生成
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>CUITNet</string>
  <key>CFBundleDisplayName</key><string>CUIT 校园网</string>
  <key>CFBundleIdentifier</key><string>com.ikuyu.cuitnet</string>
  <key>CFBundleExecutable</key><string>CUITNet</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${VERSION}</string>
  <key>CFBundleVersion</key><string>${BUILD}</string>
  <key>CFBundleDevelopmentRegion</key><string>zh_CN</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
  <key>NSHumanReadableCopyright</key><string>MIT License</string>
  <!-- 门户和联网探测都是明文 HTTP -->
  <key>NSAppTransportSecurity</key>
  <dict><key>NSAllowsArbitraryLoads</key><true/></dict>
  <key>NSLocalNetworkUsageDescription</key>
  <string>需要访问校园网认证服务器以完成登录。</string>
</dict>
</plist>
PLIST

if [[ -n "${SIGN_IDENTITY:-}" ]]; then
  codesign --force --options runtime --timestamp \
    --entitlements CUITNet.entitlements --sign "$SIGN_IDENTITY" "$APP"
  echo "已用 Developer ID 签名：$SIGN_IDENTITY"
else
  codesign --force --sign - "$APP"
  echo "未设置 SIGN_IDENTITY，已做 ad-hoc 签名（仅限本机调试）"
fi
codesign --verify --strict --verbose=2 "$APP"
