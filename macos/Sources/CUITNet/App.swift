import AppKit
import SwiftUI

@main
struct CUITNetApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model = AppModel.shared

    var body: some Scene {
        MenuBarExtra {
            MenuPanel()
                .environment(model)
        } label: {
            Image(systemName: model.status.symbol)
                .accessibilityLabel("CUIT 校园网：\(model.status.title)")
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // 首次运行还没有账号：直接弹出设置窗口
        if !AppModel.shared.hasAccount { SettingsWindow.show() }
        #if DEBUG
        // 截图预览菜单栏面板：CUITNET_PREVIEW_PANEL=1 swift run
        if ProcessInfo.processInfo.environment["CUITNET_PREVIEW_PANEL"] != nil {
            let w = NSWindow(contentViewController: NSHostingController(rootView: MenuPanel().environment(AppModel.shared)))
            w.title = "面板预览"
            w.center()
            w.makeKeyAndOrderFront(nil)
            NSApp.activate()
            panelPreview = w
        }
        #endif
    }

    #if DEBUG
    private var panelPreview: NSWindow?
    #endif
}

/// 菜单栏 App 没有常规窗口，设置窗口由 AppKit 托管，保证随时能唤出到前台。
@MainActor
enum SettingsWindow {
    private static var window: NSWindow?

    static func show() {
        if window == nil {
            let host = NSHostingController(rootView: SettingsView().environment(AppModel.shared))
            let w = NSWindow(contentViewController: host)
            w.title = "CUIT 校园网"
            w.styleMask = [.titled, .closable, .fullSizeContentView]
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}
