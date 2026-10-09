import Foundation

public enum NetState: Sendable, Equatable {
    case online
    case captive(URL?)   // 被门户拦截；附带网关给的门户入口
    case noNetwork
}

public struct Probe: Sendable {
    public let url: URL
    public let status: Int?        // nil = 只要不被劫持就算在线
    public let contains: String?

    public init(_ url: String, status: Int?, contains: String? = nil) {
        self.url = URL(string: url)!
        self.status = status
        self.contains = contains
    }

    /// 223.5.5.5 是纯 IP：断网时 DNS 不通也能被网关劫持，从而拿到门户地址。
    public static let standard: [Probe] = [
        Probe("http://connect.rom.miui.com/generate_204", status: 204),
        Probe("http://www.msftconnecttest.com/connecttest.txt", status: 200, contains: "Microsoft Connect Test"),
        Probe("http://captive.apple.com/hotspot-detect.html", status: 200, contains: "Success"),
        Probe("http://223.5.5.5/", status: nil),
    ]
}

public enum Connectivity {
    public static func check(_ http: HTTPClient, probes: [Probe] = Probe.standard) async -> NetState {
        var reachable = false
        for p in probes {
            guard let r = try? await http.get(p.url, timeout: 4) else { continue }
            reachable = true
            if let entry = portalEntry(r) { return .captive(entry) }
            if let want = p.status {
                if r.status == want && (p.contains.map { r.text.contains($0) } ?? true) { return .online }
            } else if !r.isRedirect {
                return .online
            }
        }
        return reachable ? .captive(nil) : .noNetwork
    }

    static func portalEntry(_ r: HTTPResponse) -> URL? {
        if r.isRedirect, let loc = r.location, isPrivate(loc) { return loc }
        guard r.status == 200 else { return nil }
        let body = String(r.text.prefix(8000))
        for pattern in [#"<meta[^>]+http-equiv=["']?refresh["']?[^>]+url=([^"'>\s]+)"#,
                        #"location\.(?:replace|href)\s*[=(]\s*["']([^"']+)["']"#] {
            guard let re = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
                  let m = re.firstMatch(in: body, range: NSRange(body.startIndex..., in: body)),
                  let range = Range(m.range(at: 1), in: body),
                  let url = URL(string: String(body[range]), relativeTo: r.url)?.absoluteURL,
                  isPrivate(url) else { continue }
            return url
        }
        return nil
    }

    static func isPrivate(_ url: URL) -> Bool {
        let parts = (url.host ?? "").split(separator: ".").compactMap { Int($0) }
        guard parts.count == 4 else { return false }
        switch (parts[0], parts[1]) {
        case (10, _), (192, 168), (127, _): return true
        case (172, 16...31): return true
        default: return false
        }
    }
}

public struct Credentials: Sendable {
    public var username: String
    public var password: String
    public var carrier: Carrier

    public init(username: String, password: String, carrier: Carrier) {
        self.username = username
        self.password = password
        self.carrier = carrier
    }
}

public struct LoginOutcome: Sendable {
    public let message: String
    public let carrier: String?
    public let learnedPortal: URL
    public let learnedNAS: String?   // 新学到的真实接入设备地址，调用方应保存
}

/// 一次完整的登录。已在线时直接返回（force 除外）。
public func performLogin(_ creds: Credentials, portal: URL = PortalClient.defaultPortal, nasIP: String = "",
                         force: Bool = false, probes: [Probe] = Probe.standard,
                         http: HTTPClient = HTTPClient()) async throws -> LoginOutcome {
    let state = await Connectivity.check(http, probes: probes)
    if state == .online && !force {
        return LoginOutcome(message: "已经在线", carrier: nil, learnedPortal: portal, learnedNAS: nil)
    }
    var entry: URL? = nil
    if case .captive(let e) = state { entry = e }

    let client = PortalClient(portal: portal, nasIP: nasIP, http: http)
    let session: PortalSession
    do {
        session = try await client.openSession(captiveEntry: entry)
    } catch let e as URLError {
        throw PortalError.failed("连不上认证服务器（不在校园网内？）：\(e.localizedDescription)")
    }
    try await client.authenticate(session, username: creds.username, password: creds.password)
    let name = try await client.selectService(session, carrier: creds.carrier)
    let nas = session.hasRealNAS && session.nasIP != nasIP ? session.nasIP : nil
    return LoginOutcome(message: "登录成功（\(name)）", carrier: name, learnedPortal: client.portal, learnedNAS: nas)
}
