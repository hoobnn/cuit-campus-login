import AppKit
import CUITNetCore
import Network
import Observation
import ServiceManagement
import UserNotifications

enum Status: Equatable {
    case checking, online, captive, noNetwork, working(String), rejected(String), failed(String)

    var title: String {
        switch self {
        case .checking: return "正在检测…"
        case .online: return "已联网"
        case .captive: return "未认证"
        case .noNetwork: return "没有网络"
        case .working(let what): return what
        case .rejected: return "账号被拒"
        case .failed: return "登录失败"
        }
    }

    var symbol: String {
        switch self {
        case .online: return "wifi"
        case .captive, .failed: return "wifi.exclamationmark"
        case .rejected: return "person.crop.circle.badge.exclamationmark"
        case .noNetwork: return "wifi.slash"
        case .checking, .working: return "arrow.triangle.2.circlepath"
        }
    }

    var tint: NSColor {
        switch self {
        case .online: return .systemGreen
        case .captive, .failed: return .systemOrange
        case .rejected, .noNetwork: return .systemRed
        case .checking, .working: return .systemBlue
        }
    }

    var isBusy: Bool {
        switch self { case .checking, .working: return true; default: return false }
    }
}

struct ActivityEntry: Identifiable {
    let id = UUID()
    let date = Date()
    let text: String
    let isError: Bool
}

@MainActor @Observable
final class AppModel {
    static let shared = AppModel()

    private(set) var status: Status = .checking
    private(set) var activity: [ActivityEntry] = []
    private(set) var launchAtLogin = SMAppService.mainApp.status == .enabled

    var username: String { didSet { defaults.set(username, forKey: "username") } }
    var carrier: Carrier { didSet { defaults.set(carrier.rawValue, forKey: "carrier") } }
    var portal: String { didSet { defaults.set(portal, forKey: "portal") } }
    var keepOnline: Bool {
        didSet { defaults.set(keepOnline, forKey: "keepOnline"); keepOnline ? startMonitor() : stopMonitor() }
    }
    private(set) var nasIP: String { didSet { defaults.set(nasIP, forKey: "nasIP") } }

    var hasAccount: Bool { !username.isEmpty && Keychain.load(account: username) != nil }

    private let defaults = UserDefaults.standard
    private var monitor: Task<Void, Never>?
    private var sleeper: Task<Void, Never>?
    private let path = NWPathMonitor()
    private var rejectedFingerprint: String?
    private let logURL: URL

    private init() {
        username = defaults.string(forKey: "username") ?? ""
        carrier = Carrier(rawValue: defaults.string(forKey: "carrier") ?? "") ?? .cmcc
        portal = defaults.string(forKey: "portal") ?? PortalClient.defaultPortal.absoluteString
        nasIP = defaults.string(forKey: "nasIP") ?? ""
        keepOnline = defaults.object(forKey: "keepOnline") as? Bool ?? true
        let logs = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs/CUITNet", isDirectory: true)
        try? FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        logURL = logs.appendingPathComponent("cuitnet.log")

        // 网络切换（换 Wi-Fi、插网线）或从睡眠唤醒时立刻重新检查，不用等下一个周期
        path.pathUpdateHandler = { [weak self] _ in Task { @MainActor in self?.poke() } }
        path.start(queue: .main)
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in Task { @MainActor in self?.poke() } }

        if keepOnline { startMonitor() } else { Task { await refresh() } }
    }

    // MARK: 账号

    func saveAccount(username newName: String, password: String, carrier newCarrier: Carrier) throws {
        let name = newName.trimmingCharacters(in: .whitespaces)
        if !username.isEmpty && username != name { Keychain.delete(account: username) }
        if !password.isEmpty { try Keychain.save(password, account: name) }
        username = name
        carrier = newCarrier
        record("已保存账号 \(name)（\(newCarrier.displayName)）")
        poke()
    }

    func password() -> String { Keychain.load(account: username) ?? "" }

    // MARK: 动作

    func refresh() async {
        status = .checking
        status = Self.map(await Connectivity.check(HTTPClient()))
    }

    func loginNow() {
        rejectedFingerprint = nil
        Task { _ = await attemptLogin(force: false) }
    }

    func logoutNow() {
        Task {
            status = .working("正在下线…")
            let wasKeeping = keepOnline
            if wasKeeping { keepOnline = false }  // 否则马上又被自动登录
            do {
                try await PortalClient(portal: portalURL, nasIP: nasIP).logout()
                record("已下线，已暂停自动保持在线")
            } catch {
                record("下线失败：\(error.localizedDescription)。可在自助服务中心手动下线", error: true)
            }
            await refresh()
        }
    }

    func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            record("设置开机启动失败：\(error.localizedDescription)", error: true)
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
        if SMAppService.mainApp.status == .requiresApproval {
            record("请在「系统设置 › 通用 › 登录项」里允许 CUIT 校园网", error: true)
            SMAppService.openSystemSettingsLoginItems()
        }
    }

    func openLog() { NSWorkspace.shared.open(logURL) }

    func openSelfService() {
        if let url = URL(string: portal.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/self/index") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: 守护

    /// 网络变化 / 唤醒 / 改了账号：打断当前等待，立刻检查一轮。
    private func poke() {
        if monitor != nil { sleeper?.cancel() } else { Task { await refresh() } }
    }

    private func startMonitor() {
        guard monitor == nil else { return }
        monitor = Task { [weak self] in
            var backoff: Double = 0
            while !Task.isCancelled {
                guard let self else { return }
                let delay = await self.tick(backoff: &backoff)
                let nap = Task { _ = try? await Task.sleep(for: .seconds(delay)) }
                self.sleeper = nap
                await nap.value
            }
        }
    }

    private func stopMonitor() {
        monitor?.cancel()
        sleeper?.cancel()
        monitor = nil
        Task { await refresh() }
    }

    /// 一轮检查，返回距离下一轮的秒数。
    private func tick(backoff: inout Double) async -> Double {
        if let fp = rejectedFingerprint {
            if fp == fingerprint() { return 30 }  // 账号没改就不重试，防止锁号
            rejectedFingerprint = nil
        }
        await refresh()
        if status == .online { backoff = 0; return 60 }
        guard hasAccount else { return 30 }
        if await attemptLogin(force: false) { backoff = 0; return 60 }
        if case .rejected = status { rejectedFingerprint = fingerprint(); return 30 }
        backoff = min(max(backoff * 2, 10), 300)
        return backoff
    }

    @discardableResult
    private func attemptLogin(force: Bool) async -> Bool {
        guard hasAccount else {
            record("请先在「设置」里填写学号和密码", error: true)
            status = .failed("未设置账号")
            return false
        }
        status = .working("正在登录…")
        do {
            let out = try await performLogin(
                Credentials(username: username, password: password(), carrier: carrier),
                portal: portalURL, nasIP: nasIP, force: force)
            if let nas = out.learnedNAS { nasIP = nas }
            if out.learnedPortal != portalURL { portal = out.learnedPortal.absoluteString }
            record(out.message)
            if out.carrier != nil { notify("校园网已连接", out.message) }
            await refresh()
            return status == .online || out.carrier != nil
        } catch let e as PortalError where e.isRejected {
            status = .rejected(e.localizedDescription)
            record("\(e.localizedDescription)。已停止自动重试，请检查密码或运营商", error: true)
            notify("校园网登录被拒", e.localizedDescription)
            return false
        } catch {
            status = .failed(error.localizedDescription)
            record(error.localizedDescription, error: true)
            return false
        }
    }

    private var portalURL: URL { URL(string: portal) ?? PortalClient.defaultPortal }

    private func fingerprint() -> String { "\(username)|\(carrier.rawValue)|\(password().hashValue)" }

    private static func map(_ s: NetState) -> Status {
        switch s {
        case .online: return .online
        case .captive: return .captive
        case .noNetwork: return .noNetwork
        }
    }

    // MARK: 记录

    private func record(_ text: String, error: Bool = false) {
        activity.insert(ActivityEntry(text: text, isError: error), at: 0)
        if activity.count > 50 { activity.removeLast() }
        let line = "\(Date().formatted(.iso8601)) \(error ? "ERROR" : "INFO ") \(text)\n"
        if let h = try? FileHandle(forWritingTo: logURL) {
            h.seekToEndOfFile(); h.write(Data(line.utf8)); try? h.close()
        } else {
            try? Data(line.utf8).write(to: logURL)
        }
    }

    private func notify(_ title: String, _ body: String) {
        Task {
            let center = UNUserNotificationCenter.current()
            guard (try? await center.requestAuthorization(options: [.alert])) == true else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            try? await center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
        }
    }
}
