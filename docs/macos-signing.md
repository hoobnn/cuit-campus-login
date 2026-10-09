# macOS 签名与公证

发布给其他人的 macOS 安装包必须经过 Developer ID 签名和 Apple 公证，否则 Gatekeeper 会拦截。
本仓库的流程：

```text
构建 → Developer ID 签名（Hardened Runtime + 安全时间戳）
     → 公证 App 并钉上票据 → 打 DMG → 签名 DMG → 公证 DMG 并钉上票据 → Gatekeeper 校验
```

App 本身也钉上票据，是因为用户第一次打开它时，往往还没登录校园网、处于断网状态，
Gatekeeper 需要离线就能完成校验。

## 需要准备

1. **Developer ID Application 证书**（Apple Developer Program 账号）
2. **App Store Connect API Key**：用于 `notarytool` 公证。
   在 [App Store Connect › 用户和访问 › 集成 › App Store Connect API](https://appstoreconnect.apple.com/access/integrations/api)
   新建「团队密钥」，角色选「开发者」即可。下载 `AuthKey_<KEY_ID>.p8`（只能下载一次），
   记下 Key ID 和页面顶部的 Issuer ID。

## 本地发布

```bash
# 一次性：把公证凭据存进钥匙串
xcrun notarytool store-credentials cuitnet-notary \
  --key AuthKey_XXXXXXXXXX.p8 --key-id XXXXXXXXXX --issuer xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx

# 查看可用的签名证书
security find-identity -v -p codesigning | grep "Developer ID Application"

cd macos
export SIGN_IDENTITY="Developer ID Application: 姓名 (TEAMID)"
export NOTARY_PROFILE=cuitnet-notary
scripts/release.sh 0.1.0        # 产物：build/CUITNet-0.1.0.dmg
```

单独使用的脚本：

| 脚本 | 作用 |
| --- | --- |
| `scripts/build-app.sh [版本] [构建号]` | 构建并签名 `build/CUITNet.app`（无 `SIGN_IDENTITY` 时 ad-hoc 签名） |
| `scripts/notarize.sh <app/dmg>` | 公证并钉票据，失败时打印 Apple 返回的日志 |
| `scripts/make-dmg.sh <app> <dmg>` | 打拖拽安装 DMG，有 `SIGN_IDENTITY` 时一并签名 |
| `scripts/release.sh <版本> [构建号]` | 串起以上全部步骤并做 Gatekeeper 校验 |

## GitHub Actions

在仓库 Settings › Secrets and variables › Actions 里配置这些 secrets：

| Secret | 内容 |
| --- | --- |
| `MACOS_CERT_P12_BASE64` | Developer ID 证书（含私钥）导出的 `.p12`，Base64 编码 |
| `MACOS_CERT_PASSWORD` | 导出 `.p12` 时设置的密码 |
| `MACOS_SIGN_IDENTITY` | 证书全名，如 `Developer ID Application: 姓名 (TEAMID)` |
| `NOTARY_KEY_P8_BASE64` | `AuthKey_<KEY_ID>.p8`，Base64 编码 |
| `NOTARY_KEY_ID` | API Key ID |
| `NOTARY_ISSUER_ID` | Issuer ID |

导出证书：打开「钥匙串访问」›「我的证书」，右键对应的 Developer ID Application 证书 ›「导出」，
保存为 `.p12` 并设置密码。然后用 `gh` 写入 secrets：

```bash
base64 -i DeveloperID.p12 | gh secret set MACOS_CERT_P12_BASE64
gh secret set MACOS_CERT_PASSWORD
gh secret set MACOS_SIGN_IDENTITY --body "Developer ID Application: 姓名 (TEAMID)"
base64 -i AuthKey_XXXXXXXXXX.p8 | gh secret set NOTARY_KEY_P8_BASE64
gh secret set NOTARY_KEY_ID --body XXXXXXXXXX
gh secret set NOTARY_ISSUER_ID --body xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
rm DeveloperID.p12   # 导出的证书文件用完即删
```

CI 的行为：

- **推送 `v*` 标签**：导入证书到临时钥匙串 → `release.sh` 签名、公证、打 DMG → 发布到 Release。
- **普通推送 / PR**：有证书就用 Developer ID 签名，没有（例如 fork 来的 PR）就 ad-hoc 签名；都不公证。
- 临时钥匙串和 `.p8` 文件在任务结束时一律删除，无论成功失败。

## 排查

```bash
codesign -dvv build/CUITNet.app                 # 看签名身份、Team ID、runtime 标记、时间戳
spctl --assess --type execute -vv build/CUITNet.app
xcrun stapler validate build/CUITNet-0.1.0.dmg
xcrun notarytool history --keychain-profile cuitnet-notary
```

`spctl` 显示 `source=Unnotarized Developer ID` 表示签名正确但还没公证；
显示 `source=Notarized Developer ID` 才可以分发。
