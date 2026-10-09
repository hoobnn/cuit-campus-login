# 发布流程

打 `v*` 标签即触发 `.github/workflows/release.yml`：

```text
单元测试（macOS + Windows）
  → macOS：构建 → Developer ID 签名 → Apple 公证 → Sparkle 签名 → zip / dmg → 发布 GitHub Release
  → Windows：发布单文件 exe（自包含版 + 精简版）并附到同一个 Release
  → 同步 Homebrew cask（hoobnn/homebrew-tap 的 Casks/cuitnet.rb）
  → 重新部署 Pages，appcast.xml 随之更新，已安装的用户通过 Sparkle 收到更新
```

签名、公证、Sparkle 签名、cask 同步与 appcast 生成都放在
[`hoobnn/ci-workflows`](https://github.com/hoobnn/ci-workflows)，本仓库只描述"怎么构建"。
平时推送 main 和 PR 只跑 `.github/workflows/ci.yml`（两端单元测试 + 未签名构建校验）。

## 一次性配置

`Settings → Secrets and variables → Actions`：

| 类型 | 名称 | 内容 |
|---|---|---|
| Secret | `APPLE_CERT_APPLICATION_P12_BASE64` | Developer ID Application 证书 `.p12` 的 base64 |
| Secret | `APPLE_CERT_APPLICATION_P12_PASSWORD` | 导出 `.p12` 时设的密码 |
| Secret | `APPLE_NOTARY_KEY_ID` | App Store Connect API Key ID |
| Secret | `APPLE_NOTARY_ISSUER_ID` | Issuer ID |
| Secret | `APPLE_NOTARY_KEY_P8_BASE64` | `AuthKey_XXXX.p8` 的 base64 |
| Secret | `HOMEBREW_TAP_TOKEN` | fine-grained token，只授权 `hoobnn/homebrew-tap` 的 Contents 读写 |
| Secret | `SPARKLE_ED_PRIVATE_KEY` | Sparkle EdDSA 私钥（已配置） |
| Variable | `APPLE_TEAM_ID` | `8FUPL8QHFH` |
| Variable | `APPLE_SIGN_IDENTITY_APPLICATION` | `Developer ID Application: 名字 (TeamID)`，同名冲突时填 SHA-1 指纹 |

证书与 API Key 的导出方法同
[Keyboard Logo Fix 的发布文档](https://github.com/hoobnn/macos-keyboard-logo-fix/blob/main/docs/RELEASE.md)。
几个应用共用同一张证书和同一个 API Key，但每个仓库各自配置 secrets。

Sparkle 私钥存在登录钥匙串里（账号 `cuitnet`），与 `macos/Resources/Info.plist` 里的 `SUPublicEDKey` 配对。
**私钥丢失后，已安装的用户将无法再收到更新**，请备份：

```bash
cd macos && swift package resolve
.build/artifacts/sparkle/Sparkle/bin/generate_keys --account cuitnet -x cuitnet-sparkle-private-key
# 把导出的文件放进密码管理器后删除
```

GitHub Pages 的 Source 需设为 **GitHub Actions**。

## 发布一个版本

```bash
# 1. 改版本号：macos/Resources/Info.plist 的 CFBundleShortVersionString 与 CFBundleVersion
#    （Windows 版本号由 CI 从这里传入，无需单独修改）
# 2. 提交并打标签，标签必须与 CFBundleShortVersionString 一致，否则 CI 会拒绝
git commit -am "🔧 chore: 发布 0.2.0"
git tag v0.2.0
git push && git push --tags
```

第一次发版前，先在 tap 里添加 `Casks/cuitnet.rb`（cask 同步只改写已有文件的版本号和 sha256）。

## 本地构建

```bash
cd macos
scripts/build-app.sh                                   # ad-hoc 签名，仅本机可用
APPLE_SIGN_IDENTITY_APPLICATION="Developer ID Application: 名字 (TeamID)" scripts/build-app.sh
codesign -dv build/CUITNet.app                         # flags 应含 runtime
```

## 验证已发布产物

```bash
spctl --assess --type execute --verbose=2 /Applications/CUITNet.app   # source=Notarized Developer ID
xcrun stapler validate /Applications/CUITNet.app
curl -s https://hoobnn.github.io/cuit-campus-login/appcast.xml        # 最新版本应在最前
```
