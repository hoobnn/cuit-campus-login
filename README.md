# CUIT 校园网

![CUIT 校园网图标](windows/src/CUITNet.App/app.png)

成都信息工程大学校园网自动登录，macOS 与 Windows 原生应用。

连上校园网后自动完成认证，掉线自动重连。直接按门户协议发 HTTP 请求，不打开浏览器、不依赖浏览器驱动。

| | macOS | Windows |
| --- | --- | --- |
| 技术栈 | Swift 6 · SwiftUI · 菜单栏应用 | C# · .NET 9 · WPF（Windows 11 Fluent 主题）· 托盘应用 |
| 密码存储 | 钥匙串 | 凭据管理器 |
| 开机启动 | `SMAppService` 登录项 | 注册表 `HKCU\…\Run` |
| 网络变化感知 | `NWPathMonitor` + 睡眠唤醒 | `NetworkChange` + 电源恢复 |
| 系统要求 | macOS 14+，Apple 芯片 / Intel 通用 | Windows 10 1809+ x64 |

## 功能

- **一键登录**：自动完成账号密码认证和运营商选择（移动 / 电信 / 联通）
- **自动保持在线**：后台检测，被门户拦截就重新登录；失败按 10 秒 → 5 分钟退避；换网络、从睡眠唤醒时立即检测
- **防锁号**：门户提示密码错误后立即停手，不再重试；改好密码后自动恢复
- **绕开系统代理**：认证请求强制直连，开着 Clash 等代理也能登录
- **系统通知**：自动重连成功、密码被拒时提醒

## 下载

到 [Releases](../../releases) 下载：

- **macOS**：`CUITNet-macos-<版本>.zip`，解压后把「CUIT 校园网」拖进「应用程序」。首次打开未签名应用会被拦截：右键 →「打开」，或在「系统设置 › 隐私与安全性」点「仍要打开」。
- **Windows**：`CUITNet.exe`（自带运行时，约 74 MB，双击即用）；已装 [.NET 9 桌面运行时](https://dotnet.microsoft.com/download/dotnet/9.0) 的可以下载 `CUITNet-lite.exe`（约 1 MB）。

首次打开填学号、密码、选运营商即可。macOS 版常驻菜单栏，Windows 版关闭窗口后留在托盘。

## 仓库结构

```text
macos/      Swift Package：CUITNetCore（协议）+ CUITNet（SwiftUI 菜单栏应用）
windows/    CUITNet.Core（协议，net9.0）+ CUITNet.App（WPF）+ 测试
testing/    两端共用的本地假门户 fake_portal.py（端到端测试用）
assets/icon 手绘喜鹊图标的 SVG 源文件与生成脚本
```

## 构建与测试

两端都用同一个本地假门户（`testing/fake_portal.py`，按真实门户的跳转和接口行为模拟，只用 Python 标准库）做端到端测试，需要 `python3`。

```bash
# macOS（需要 Xcode 16+）
cd macos && swift test
scripts/build-app.sh 0.1.0          # 生成 build/CUITNet.app 和 zip

# Windows（.NET 9 SDK；在 macOS 上也能编译和跑核心测试）
cd windows && dotnet test tests/CUITNet.Core.Tests
dotnet publish src/CUITNet.App -c Release -r win-x64 --self-contained -p:PublishSingleFile=true -o publish

# 修改图标 SVG 后重新生成各平台图标（macOS）
assets/icon/build.sh
```

推送 `v*` 标签会由 GitHub Actions 构建两端安装包并发布 Release。

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

- 协议实现和测试基于社区对真实门户的逆向结果；作者本机不在校园网内，**尚未在真实门户上实测**。遇到问题请附上日志提 issue（macOS：菜单栏面板 →「日志」；Windows：主界面 →「打开日志」）。
- 下线接口（`/eportal/network/offline`）验证较少；失败时可在自助服务中心 `http://10.254.241.66/self/index` 手动下线。
- macOS 版未经 Apple 公证，首次打开需要手动放行。

## 致谢

协议细节参考了这些项目的逆向成果：

- [miaoxi-awa/CUIT-Auto-Campus-Login](https://github.com/miaoxi-awa/CUIT-Auto-Campus-Login)：Selenium 版，本项目的起点
- [March7awa/cuit-net-login](https://github.com/March7awa/cuit-net-login)（MIT）：CAS 链路与 AES 加密的逆向文档
- [DECKS555/campus-login](https://github.com/DECKS555/campus-login)（MIT）：serviceLogin 判定方式
- [gs-eng/cuitauto](https://github.com/gs-eng/cuitauto)：门户接口梳理

## License

MIT
