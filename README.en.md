<div align="center">

<img src="windows/src/CUITNet.App/app.png" width="112" alt="CUITNet app icon: a hand-drawn magpie">

# CUITNet: auto-login for the CUIT campus network

Native macOS and Windows apps that sign in to the campus network automatically and reconnect when the connection drops.

[![Release](https://img.shields.io/github/v/release/hoobnn/cuit-campus-login?style=flat-square)](https://github.com/hoobnn/cuit-campus-login/releases/latest)
[![CI](https://img.shields.io/github/actions/workflow/status/hoobnn/cuit-campus-login/ci.yml?branch=main&style=flat-square&label=CI)](https://github.com/hoobnn/cuit-campus-login/actions/workflows/ci.yml)
[![macOS](https://img.shields.io/badge/macOS-14%2B-black?style=flat-square&logo=apple)](#macos)
[![Windows](https://img.shields.io/badge/Windows-10%201809%2B-0078D4?style=flat-square)](#windows)
[![Homebrew](https://img.shields.io/badge/brew-cuitnet-FBB040?style=flat-square&logo=homebrew&logoColor=white)](#macos)
[![License](https://img.shields.io/badge/license-MIT-green?style=flat-square)](LICENSE)

</div>

[简体中文](README.md) | English

CUITNet is a free, open-source (MIT) auto-login tool for the campus network of Chengdu University of Information Technology (CUIT, 成都信息工程大学). It is a native macOS app (Swift / SwiftUI menu bar) and a native Windows app (.NET 9 / WPF tray) that talk to the campus captive portal (Ruijie SAM 5.x with CAS single sign-on) directly over HTTP, with no browser and no Selenium. When the portal intercepts traffic, the app signs in again by itself. The macOS app lives in the menu bar; the Windows app stays in the tray after you close the window.

## Features

- **One-click login**: account and password authentication plus carrier selection (China Mobile / Telecom / Unicom).
- **Stays online**: background checks; if the portal intercepts traffic it logs in again. Failures back off from 10 seconds up to 5 minutes. Checks run immediately after a network change or wake from sleep.
- **Lockout protection**: once the portal reports a wrong password the app stops retrying, and resumes after you fix the password.
- **Bypasses system proxies**: authentication requests connect directly, so it works while Clash or similar proxies are on.
- **Notifications**: tells you when it reconnects or when the password is rejected.
- **Launch at login**: switchable in settings.

## Install

### macOS

```bash
brew install --cask hoobnn/tap/cuitnet
```

Or download `CUITNet-<version>-macOS.dmg` from [Releases](https://github.com/hoobnn/cuit-campus-login/releases/latest), open it and drag CUITNet into Applications. Requires macOS 14 or later, Apple silicon and Intel. The installer is Developer ID signed and notarized by Apple.

### Windows

Download from [Releases](https://github.com/hoobnn/cuit-campus-login/releases/latest):

- `CUITNet-<version>-Windows.exe`: bundles the runtime, about 74 MB, double-click to run.
- `CUITNet-<version>-Windows-lite.exe`: about 1 MB, requires the [.NET 9 Desktop Runtime](https://dotnet.microsoft.com/download/dotnet/9.0).

Requires Windows 10 1809 or later (x64). The app is not code-signed yet; if SmartScreen warns on first run, click "More info" then "Run anyway".

### Updates and uninstall

- macOS: in-app updates via [Sparkle](https://sparkle-project.org) (EdDSA-signed packages), or `brew upgrade --cask cuitnet`. Uninstall with `brew uninstall --cask cuitnet` (add `--zap` to remove preferences and logs). The credentials are in the Keychain under service `CUITNet`.
- Windows: no in-app update yet; download the new release and replace the exe. To uninstall, turn off launch at login in the app, then delete the exe. Config and logs are in `%APPDATA%\CUITNet`; the password is in Credential Manager (`CUITNet:<student ID>`).

## First run

Enter your student ID and password, pick the carrier, and you are done. The app keeps you online in the background. Logs: macOS menu bar panel, "Logs"; Windows main window, "Open log".

## How it works

```text
probe internet ──online──> do nothing
   │
intercepted by the portal (gateway 302)
   │
1. follow redirects to get sessionId / nasIp / userIp
2. POST /eportal/workFlow/getCurrentNode
3. GET  /cas-sso/login             → AES key and execution from the page
4. POST /cas-sso/login             → password encrypted with AES-128-ECB
5. POST /eportal/network/serviceSelection + serviceLogin → choose carrier, get access
```

Password encryption matches the portal's CryptoJS front end byte for byte, verified on both platforms against ciphertext captured from the real portal.

## FAQ

**How do I auto-login to the CUIT campus network?**
Install the app, enter your student ID and password once, and pick the carrier. It then checks the connection in the background and signs in again whenever the portal intercepts traffic.

**Do I need a browser or Selenium?**
No. The app sends the portal's HTTP requests itself; there is no browser, driver or Python dependency.

**Which systems are supported?**
macOS 14+ (Apple silicon and Intel) and Windows 10 1809+ (x64). Linux and mobile are not supported.

**Where is my password stored?**
In the macOS Keychain (service `CUITNet`) or Windows Credential Manager (`CUITNet:<student ID>`), not in a plain-text config file. Authentication requests go only to the campus portal.

**Can it lock my account by retrying a wrong password?**
No. After the portal reports a wrong password the app stops retrying until you change it.

**Does it work with Clash or other proxies on?**
Yes. Authentication requests connect directly and ignore the system proxy.

**Does it actually work?**
The protocol follows the community's reverse-engineering of the real portal and is end-to-end tested against a local fake portal. The author is not on the campus network, so it has **not been tested against the real portal**, and the Windows UI has not been run on a real machine. Please open an [issue](https://github.com/hoobnn/cuit-campus-login/issues) with your log if something fails.

**Is it free? Does it work for other universities?**
Free under the MIT license. The implementation targets CUIT's portal (Ruijie SAM 5.x + CAS); other schools use different endpoints and are not guaranteed to work.

**What are the alternatives?**
For a Python + Selenium script, see [miaoxi-awa/CUIT-Auto-Campus-Login](https://github.com/miaoxi-awa/CUIT-Auto-Campus-Login), the starting point of this project. For a native app with menu bar / tray, no browser and launch at login, use this one.

## Known limitations

- The protocol implementation and tests are based on the community's reverse-engineering of the real portal; **not yet verified against the real portal**. Please attach logs to an [issue](https://github.com/hoobnn/cuit-campus-login/issues).
- The logout endpoint (`/eportal/network/offline`) is less tested; if it fails, log out manually at the self-service center `http://10.254.241.66/self/index`.

## Build from source

Both platforms are tested end to end against the same local fake portal (`testing/fake_portal.py`, Python standard library only), so `python3` is required.

```bash
# macOS (Xcode 16+)
cd macos && swift test
scripts/build-app.sh                # builds build/CUITNet.app (ad-hoc signed without a signing identity)

# Windows (.NET 9 SDK; also compiles and runs core tests on macOS)
cd windows && dotnet test tests/CUITNet.Core.Tests
dotnet publish src/CUITNet.App -c Release -r win-x64 --self-contained -p:PublishSingleFile=true -o publish
```

Layout: `macos/` (Swift package: CUITNetCore protocol + SwiftUI menu bar app), `windows/` (CUITNet.Core + WPF app + tests), `testing/` (fake portal), `assets/icon` (icon SVG sources), `site/` (product page and Sparkle appcast). Release process: [docs/RELEASE.md](docs/RELEASE.md).

## Acknowledgements

Protocol details draw on these reverse-engineering efforts:

- [miaoxi-awa/CUIT-Auto-Campus-Login](https://github.com/miaoxi-awa/CUIT-Auto-Campus-Login): the Selenium version this project started from
- [March7awa/cuit-net-login](https://github.com/March7awa/cuit-net-login) (MIT): CAS flow and AES encryption notes
- [DECKS555/campus-login](https://github.com/DECKS555/campus-login) (MIT): how to judge serviceLogin results
- [gs-eng/cuitauto](https://github.com/gs-eng/cuitauto): portal endpoint notes

## License

[MIT](LICENSE) © 2026 hoobnn. Free to use, modify and distribute with the copyright notice kept.
