import AppKit
import Observation
import Sparkle

/// Sparkle 应用内更新。只在打包好的 .app 里启用，`swift run` 调试时不启动。
@MainActor @Observable
final class Updater: NSObject, SPUStandardUserDriverDelegate {
    static let shared = Updater()

    private(set) var canCheck = false
    private var controller: SPUStandardUpdaterController?
    private var observation: NSKeyValueObservation?

    var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "开发版"
    }

    var automaticallyChecks: Bool {
        get { controller?.updater.automaticallyChecksForUpdates ?? false }
        set { controller?.updater.automaticallyChecksForUpdates = newValue }
    }

    private override init() {
        super.init()
        guard Bundle.main.bundleURL.pathExtension == "app",
              Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") != nil else { return }
        let c = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: self)
        controller = c
        observation = c.updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] _, change in
            let value = change.newValue ?? false
            Task { @MainActor in self?.canCheck = value }
        }
    }

    func checkForUpdates() {
        NSApp.activate()  // 菜单栏应用没有前台窗口，先激活，更新窗口才会出现在最前面
        controller?.checkForUpdates(nil)
    }

    // MARK: SPUStandardUserDriverDelegate

    /// 菜单栏应用没有 Dock 图标，后台发现更新时 Sparkle 用「温和提醒」而不是突然弹窗抢焦点。
    nonisolated var supportsGentleScheduledUpdateReminders: Bool { true }

    nonisolated func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState
    ) {
        MainActor.assumeIsolated { NSApp.activate() }
    }
}
