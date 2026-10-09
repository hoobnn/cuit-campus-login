#!/bin/bash
# 把 CUITNet.app 打成拖拽安装的 DMG：scripts/make-dmg.sh <CUITNet.app> <输出.dmg>
# 设置了 SIGN_IDENTITY 时同时给 DMG 签名。
set -euo pipefail

APP="${1:?用法：make-dmg.sh <app> <dmg>}"
DMG="${2:?用法：make-dmg.sh <app> <dmg>}"

STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
ditto "$APP" "$STAGE/$(basename "$APP")"
ln -s /Applications "$STAGE/Applications"

rm -f "$DMG"
hdiutil create -volname "CUIT 校园网" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov "$DMG" >/dev/null

if [[ -n "${SIGN_IDENTITY:-}" ]]; then
  codesign --force --timestamp --sign "$SIGN_IDENTITY" "$DMG"
  codesign --verify --verbose=2 "$DMG"
fi
echo "已生成 $DMG"
