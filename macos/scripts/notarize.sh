#!/bin/bash
# 公证并钉上票据：scripts/notarize.sh <CUITNet.app | xxx.dmg>
#
# 凭据二选一：
#   NOTARY_PROFILE=<名字>                    本机：xcrun notarytool store-credentials 存进钥匙串的配置
#   NOTARY_KEY_PATH / NOTARY_KEY_ID / NOTARY_ISSUER_ID
#                                           CI：App Store Connect API Key（.p8 文件路径、Key ID、Issuer ID）
set -euo pipefail

TARGET="${1:?用法：notarize.sh <app 或 dmg 路径>}"

if [[ -n "${NOTARY_PROFILE:-}" ]]; then
  AUTH=(--keychain-profile "$NOTARY_PROFILE")
elif [[ -n "${NOTARY_KEY_PATH:-}" && -n "${NOTARY_KEY_ID:-}" && -n "${NOTARY_ISSUER_ID:-}" ]]; then
  AUTH=(--key "$NOTARY_KEY_PATH" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER_ID")
else
  echo "没有公证凭据：请设置 NOTARY_PROFILE，或 NOTARY_KEY_PATH + NOTARY_KEY_ID + NOTARY_ISSUER_ID" >&2
  exit 2
fi

# notarytool 只收 zip / dmg / pkg，.app 要先压缩
SUBMIT="$TARGET"
if [[ "$TARGET" == *.app ]]; then
  SUBMIT="$(mktemp -d)/$(basename "$TARGET" .app).zip"
  ditto -c -k --keepParent "$TARGET" "$SUBMIT"
fi

echo "提交公证：$(basename "$TARGET")（通常需要 1-5 分钟）"
OUT=$(xcrun notarytool submit "$SUBMIT" "${AUTH[@]}" --wait --output-format json)
ID=$(plutil -extract id raw - <<<"$OUT")
STATUS=$(plutil -extract status raw - <<<"$OUT")
if [[ "$STATUS" != "Accepted" ]]; then
  echo "公证失败（$STATUS），Apple 返回的日志：" >&2
  xcrun notarytool log "$ID" "${AUTH[@]}" >&2 || true
  exit 1
fi

# 钉上票据：用户首次打开时即使断网（还没登录校园网）也能通过 Gatekeeper
xcrun stapler staple "$TARGET"
xcrun stapler validate "$TARGET"
echo "公证完成：$ID"
