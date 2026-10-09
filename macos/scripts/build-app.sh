#!/bin/bash
# 构建并签名 build/CUITNet.app（arm64 + x86_64 通用二进制，内嵌 Sparkle）。
#
# 版本号以 Resources/Info.plist 为准。设置了 APPLE_SIGN_IDENTITY_APPLICATION
# （证书全名或 SHA-1 指纹）时用 Developer ID 签名并启用 Hardened Runtime 与安全时间戳；
# 否则 ad-hoc 签名，只适合本机调试。正式发布由 CI 调用 hoobnn/ci-workflows 完成，
# 见 docs/RELEASE.md。
set -euo pipefail
cd "$(dirname "$0")/.."

OUT=build
APP="$OUT/CUITNet.app"
rm -rf "$OUT" && mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"

ARCHS=(--arch arm64 --arch x86_64)
swift build -c release "${ARCHS[@]}"
cp "$(swift build -c release "${ARCHS[@]}" --show-bin-path)/CUITNet" "$APP/Contents/MacOS/CUITNet"
cp Resources/Info.plist "$APP/Contents/Info.plist"
# 图标由 assets/icon/build.sh 从 SVG 生成
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# Sparkle：应用没有沙盒化，用不到它的 XPC 服务，去掉以免多签一层
SPARKLE_SRC=.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework
test -d "$SPARKLE_SRC" || { echo "SwiftPM 没有解析出 Sparkle.framework" >&2; exit 1; }
ditto "$SPARKLE_SRC" "$APP/Contents/Frameworks/Sparkle.framework"
rm -rf "$APP/Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices" \
       "$APP/Contents/Frameworks/Sparkle.framework/XPCServices"

xattr -cr "$APP"
IDENTITY="${APPLE_SIGN_IDENTITY_APPLICATION:--}"
OPTS=(--force --sign "$IDENTITY")
[[ "$IDENTITY" != "-" ]] && OPTS+=(--options runtime --timestamp)

# 由内向外签名：Sparkle 的辅助程序 → 框架 → 应用
SPARKLE=Contents/Frameworks/Sparkle.framework/Versions/B
for inner in "$SPARKLE/Autoupdate" "$SPARKLE/Updater.app" Contents/Frameworks/Sparkle.framework; do
  codesign "${OPTS[@]}" "$APP/$inner"
done
codesign "${OPTS[@]}" --entitlements CUITNet.entitlements "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"
echo "已生成 ${APP}（签名身份：${IDENTITY}）"
