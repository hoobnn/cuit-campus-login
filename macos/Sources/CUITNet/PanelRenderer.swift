#if DEBUG
import AppKit
import SwiftUI

/// 仅调试：把菜单栏面板离屏渲染成 PNG，便于在没有屏幕录制权限时检查样式。
@MainActor
enum PanelRenderer {
    static func render(to dir: URL) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let model = AppModel.shared
        let samples: [(String, Bool)] = [
            ("登录成功（中国移动）", false),
            ("连不上认证服务器（不在校园网内？）：请求超时。", true),
            ("已保存账号 2023051234（移动）", false),
        ]
        let states: [(String, Status)] = [
            ("online", .online),
            ("captive", .captive),
            ("failed", .failed("账号或密码错误")),
            ("busy", .working("正在登录…")),
        ]
        for (name, state) in states {
            model.previewState(state, activity: samples)
            for dark in [false, true] {
                // 用真窗口 + cacheDisplay 绘制：ImageRenderer 画不出 AppKit 控件（按钮、开关）
                let host = NSHostingView(rootView: MenuPanel()
                    .environment(model)
                    .background(Color(nsColor: .windowBackgroundColor)))
                let size = host.fittingSize
                let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                                      styleMask: [.borderless], backing: .buffered, defer: false)
                window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
                window.contentView = host
                host.frame = NSRect(origin: .zero, size: size)
                host.layoutSubtreeIfNeeded()
                RunLoop.main.run(until: Date().addingTimeInterval(0.3))
                guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { continue }
                host.cacheDisplay(in: host.bounds, to: rep)
                let file = dir.appendingPathComponent("\(name)-\(dark ? "dark" : "light").png")
                try? rep.representation(using: .png, properties: [:])?.write(to: file)
            }
        }
    }
}
#endif
