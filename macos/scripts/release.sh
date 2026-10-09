#!/bin/bash
# 完整发布流程：构建 → Developer ID 签名 → 公证 App 并钉票据 → 打 DMG → 签名并公证 DMG → Gatekeeper 校验
#
# 用法：scripts/release.sh <版本号> [构建号]
#
# 环境变量：
#   SIGN_IDENTITY   必填，例如 "Developer ID Application: 姓名 (TEAMID)"
#   公证凭据        见 scripts/notarize.sh；没有凭据时跳过公证（产物只签名，不能直接分发）
#
# 产物：build/CUITNet-<版本号>.dmg
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:?用法：release.sh <版本号> [构建号]}"
BUILD="${2:-1}"
APP=build/CUITNet.app
DMG="build/CUITNet-${VERSION}.dmg"

if [[ -z "${SIGN_IDENTITY:-}" ]]; then
  echo "请设置 SIGN_IDENTITY，可用证书：" >&2
  security find-identity -v -p codesigning | grep "Developer ID Application" >&2 || true
  exit 2
fi

NOTARIZE=1
if [[ -z "${NOTARY_PROFILE:-}" && -z "${NOTARY_KEY_PATH:-}" ]]; then
  NOTARIZE=0
  echo "警告：没有公证凭据，将跳过公证（产物不能直接分发给其他用户）" >&2
fi

scripts/build-app.sh "$VERSION" "$BUILD"
[[ $NOTARIZE == 1 ]] && scripts/notarize.sh "$APP"
scripts/make-dmg.sh "$APP" "$DMG"
[[ $NOTARIZE == 1 ]] && scripts/notarize.sh "$DMG"

echo "== Gatekeeper 校验"
if [[ $NOTARIZE == 1 ]]; then
  spctl --assess --type execute --verbose=2 "$APP"
  spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG"
else
  spctl --assess --type execute --verbose=2 "$APP" || echo "（未公证，Gatekeeper 拒绝是预期结果）"
fi
echo "发布产物：$DMG"
