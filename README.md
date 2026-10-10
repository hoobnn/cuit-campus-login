<div align="center">

<img src="windows/src/CUITNet.App/app.png" width="112" alt="CUIT 校园网应用图标">

# CUIT 校园网：成都信息工程大学校园网自动登录

macOS 与 Windows 原生应用，连上校园网自动认证，掉线自动重连。

[![Release](https://img.shields.io/github/v/release/hoobnn/cuit-campus-login?style=flat-square)](https://github.com/hoobnn/cuit-campus-login/releases/latest)
[![CI](https://img.shields.io/github/actions/workflow/status/hoobnn/cuit-campus-login/ci.yml?branch=main&style=flat-square&label=CI)](https://github.com/hoobnn/cuit-campus-login/actions/workflows/ci.yml)
[![macOS](https://img.shields.io/badge/macOS-14%2B-black?style=flat-square&logo=apple)](#macos)
[![Windows](https://img.shields.io/badge/Windows-10%201809%2B-0078D4?style=flat-square)](#windows)
[![Homebrew](https://img.shields.io/badge/brew-cuitnet-FBB040?style=flat-square&logo=homebrew&logoColor=white)](#macos)
[![License](https://img.shields.io/badge/license-MIT-green?style=flat-square)](LICENSE)

</div>

CUIT 校园网直接按门户协议发 HTTP 请求完成认证，不打开浏览器，也不依赖浏览器驱动。macOS 版常驻菜单栏，Windows 版关闭窗口后留在托盘。

## 功能

- **一键登录**：自动完成账号密码认证和运营商选择（移动 / 电信 / 联通）。
- **自动保持在线**：后台检测，被门户拦截就重新登录；失败按 10 秒 → 5 分钟退避；换网络、从睡眠唤醒时立即检测。
- **防锁号**：门户提示密码错误后立即停手，不再重试；改好密码后自动恢复。
- **绕开系统代理**：认证请求强制直连，开着 Clash 等代理也能登录。
- **系统通知**：自动重连成功、密码被拒时提醒。
- **开机启动**：可在设置里开关。

## 安装

### macOS

```bash
brew install --cask hoobnn/tap/cuitnet
```

也可以从 [Releases](https://github.com/hoobnn/cuit-campus-login/releases/latest) 下载 `CUITNet-<版本>-macOS.dmg`，打开后把「CUITNet」拖进「应用程序」。需要 macOS 14 及以上，Apple 芯片和 Intel 通用。安装包经过 Developer ID 签名和 Apple 公证。

### Windows

从 [Releases](https://github.com/hoobnn/cuit-campus-login/releases/latest) 下载：

- `CUITNet-<版本>-Windows.exe`：自带运行时，约 74 MB，双击即用。
- `CUITNet-<版本>-Windows-lite.exe`：约 1 MB，需要先装 [.NET 9 桌面运行时](https://dotnet.microsoft.com/download/dotnet/9.0)。

需要 Windows 10 1809 及以上（x64）。程序暂未签名，首次运行若出现 SmartScreen 提示，点「更多信息 → 仍要运行」。

### 更新

- macOS：应用内自动检查更新（基于 [Sparkle](https://sparkle-project.org)，更新包经 EdDSA 签名校验）。Homebrew 安装的也可以用 `brew upgrade --cask cuitnet`。
- Windows：暂无应用内更新，到 Releases 下载新版替换即可。

### 卸载

- macOS：`brew uninstall --cask cuitnet`，加 `--zap` 一并清除偏好设置和日志。手动安装的，退出后从「应用程序」删除即可。账号密码存在钥匙串里（服务名 `CUITNet`），需要时在「钥匙串访问」中删除。
- Windows：先在应用里关掉开机启动，再删除 exe。配置和日志在 `%APPDATA%\CUITNet`，密码在「凭据管理器 › Windows 凭据」里（`CUITNet:<学号>`）。

## 首次使用

打开后填学号、密码，选运营商即可。之后应用会在后台保持在线，不需要再手动操作。

查看日志：macOS 点菜单栏面板 →「日志」；Windows 在主界面点「打开日志」。

## 平台差异

| | macOS | Windows |
| --- | --- | --- |
| 技术栈 | Swift 6 · SwiftUI · 菜单栏应用 | C# · .NET 9 · WPF（Windows 11 Fluent 主题）· 托盘应用 |
| 密码存储 | 钥匙串 | 凭据管理器 |
| 开机启动 | `SMAppService` 登录项 | 注册表 `HKCU\…\Run` |
| 网络变化感知 | `NWPathMonitor` + 睡眠唤醒 | `NetworkChange` + 电源恢复 |
| 应用内更新 | Sparkle 2 | 暂无 |

## 工作原理

```text
探测外网 ──在线──> 什么都不做
   │
被门户拦截（网关 302）
   │
1. 跟随跳转拿到 sessionId / nasIp / userIp
2. POST /eportal/workFlow/getCurrentNode
3. GET  /cas-sso/login             → 页面里的 AES 密钥与 execution
4. POST /cas-sso/login             → 密码经 AES-128-ECB 加密后提交
5. POST /eportal/network/serviceSelection + serviceLogin → 选运营商，放行
```

密码加密与门户前端 CryptoJS 逐字节一致，两端都用真实门户抓到的密文做了校验。

## 已知限制

- 协议实现和测试基于社区对真实门户的逆向结果；作者本机不在校园网内，**尚未在真实门户上实测**。遇到问题请附上日志提 [issue](https://github.com/hoobnn/cuit-campus-login/issues)。
- 下线接口（`/eportal/network/offline`）验证较少；失败时可在自助服务中心 `http://10.254.241.66/self/index` 手动下线。

## 从源码构建

两端都用同一个本地假门户（`testing/fake_portal.py`，按真实门户的跳转和接口行为模拟，只用 Python 标准库）做端到端测试，需要 `python3`。

```bash
# macOS（需要 Xcode 16+）
cd macos && swift test
scripts/build-app.sh                # 生成 build/CUITNet.app（内嵌 Sparkle；未设置签名证书时 ad-hoc 签名）

# Windows（.NET 9 SDK；在 macOS 上也能编译和跑核心测试）
cd windows && dotnet test tests/CUITNet.Core.Tests
dotnet publish src/CUITNet.App -c Release -r win-x64 --self-contained -p:PublishSingleFile=true -o publish

# 修改图标 SVG 后重新生成各平台图标（macOS）
assets/icon/build.sh
```

### 源码结构

```text
macos/      Swift Package：CUITNetCore（协议）+ CUITNet（SwiftUI 菜单栏应用）
windows/    CUITNet.Core（协议，net9.0）+ CUITNet.App（WPF）+ 测试
testing/    两端共用的本地假门户 fake_portal.py（端到端测试用）
assets/icon 手绘喜鹊图标的 SVG 源文件与生成脚本
site/       产品页（GitHub Pages，同时提供 Sparkle 的 appcast.xml）
```

## 发布流程

推送到 main 或提交 PR 时只运行 `.github/workflows/ci.yml`（两端单元测试 + 未签名构建校验）。推送 `v*` 标签触发 `.github/workflows/release.yml`：签名、公证、发布 Release、同步 Homebrew，并重新部署 Pages 更新 appcast。详见 [docs/RELEASE.md](docs/RELEASE.md)。

## 致谢

协议细节参考了这些项目的逆向成果：

- [miaoxi-awa/CUIT-Auto-Campus-Login](https://github.com/miaoxi-awa/CUIT-Auto-Campus-Login)：Selenium 版，本项目的起点
- [March7awa/cuit-net-login](https://github.com/March7awa/cuit-net-login)（MIT）：CAS 链路与 AES 加密的逆向文档
- [DECKS555/campus-login](https://github.com/DECKS555/campus-login)（MIT）：serviceLogin 判定方式
- [gs-eng/cuitauto](https://github.com/gs-eng/cuitauto)：门户接口梳理

[MIT](LICENSE) © 2026 hoobnn
