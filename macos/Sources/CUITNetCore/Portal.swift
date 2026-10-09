import Foundation

public enum PortalError: Error, LocalizedError, Equatable {
    /// 账号或密码被拒。不能自动重试，否则可能把账号试锁。
    case rejected(String)
    /// 门户流程出错，可以稍后重试。
    case failed(String)
    case unexpected(String)

    public var errorDescription: String? {
        switch self {
        case .rejected(let m): return "认证被拒：\(m)"
        case .failed(let m), .unexpected(let m): return m
        }
    }

    public var isRejected: Bool { if case .rejected = self { return true } else { return false } }
}

/// 运营商：界面上的名字和门户 serviceLogin 要的取值。
public enum Carrier: String, CaseIterable, Codable, Sendable, Identifiable {
    case cmcc, ctcc, unicom

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .cmcc: return "移动"
        case .ctcc: return "电信"
        case .unicom: return "联通"
        }
    }

    var aliases: [String] {
        switch self {
        case .cmcc: return ["cmcc", "移动", "中国移动", "mobile"]
        case .ctcc: return ["ctcc", "电信", "中国电信", "telecom", "chinanet"]
        case .unicom: return ["unicom", "联通", "中国联通", "cucc"]
        }
    }

    public func matches(_ text: String) -> Bool {
        aliases.contains(text.trimmingCharacters(in: .whitespaces).lowercased())
    }
}

public struct PortalSession: Sendable {
    public let portal: URL
    public let sessionID: String
    public let params: [String: String]
    public let url: URL

    public var nasIP: String { params["nasIp"] ?? "" }
    public var hasRealNAS: Bool { !["", "1.1.1.1"].contains(nasIP) }
}

/// 锐捷 SAM 5.x 门户 + CAS 单点登录（成都信息工程大学）。
///
///     1. 被劫持请求 302 -> /eportal/index.jsp -> /portal/portal-main?sessionId=...
///        拿不到劫持跳转时退回 GET {portal}/entry?mac=&nasip=
///     2. POST /eportal/workFlow/getCurrentNode
///     3. GET  /cas-sso/login    页面里有 AES 密钥（login-croypto）和 execution
///     4. POST /cas-sso/login    AES-128-ECB 加密后的密码
///     5. POST /eportal/network/serviceSelection + serviceLogin，authResult == "success" 才放行
public final class PortalClient: @unchecked Sendable {
    public private(set) var portal: URL
    public let nasIP: String
    public let http: HTTPClient

    public static let defaultPortal = URL(string: "http://10.254.241.66")!

    public init(portal: URL = PortalClient.defaultPortal, nasIP: String = "", http: HTTPClient = HTTPClient()) {
        self.portal = portal
        self.nasIP = nasIP
        self.http = http
    }

    private func headers(_ referer: URL? = nil) -> [String: String] {
        ["isPortal": "true", "Referer": (referer ?? portal).absoluteString]
    }

    private func endpoint(_ path: String, _ base: URL) -> URL {
        URL(string: path, relativeTo: base)!.absoluteURL
    }

    // MARK: 步骤 1

    /// 优先走网关的劫持跳转：只有这样门户才知道我们接在哪台接入设备上，nasIp 才是真值。
    public func openSession(captiveEntry: URL?) async throws -> PortalSession {
        var candidates: [URL] = []
        if let captiveEntry { candidates.append(captiveEntry) }
        var fallback = URLComponents(url: endpoint("/entry", portal), resolvingAgainstBaseURL: true)!
        if !nasIP.isEmpty { fallback.queryItems = [URLQueryItem(name: "nasip", value: nasIP)] }
        candidates.append(fallback.url!)

        for start in candidates {
            var url = start
            for _ in 0..<12 {
                let r = try await http.get(url, headers: headers())
                let target = r.location ?? url
                let q = Self.query(target)
                if let sid = q["sessionId"], !sid.isEmpty {
                    if let origin = Self.origin(target), origin != portal { portal = origin }
                    if r.location != nil { _ = try? await http.get(target, headers: ["Referer": url.absoluteString]) }
                    return PortalSession(portal: portal, sessionID: sid, params: q, url: target)
                }
                guard let next = r.location else { break }
                url = next
            }
        }
        throw PortalError.failed("门户没有返回 sessionId（可能已经在线，或当前不在校园网内）")
    }

    // MARK: 步骤 2-4

    public func authenticate(_ s: PortalSession, username: String, password: String) async throws {
        _ = try? await http.postJSON(endpoint("/eportal/workFlow/getCurrentNode", s.portal),
                                     ["sessionId": s.sessionID, "flowKey": s.params["flowKey"] ?? "portal_auth"],
                                     headers: headers(s.url))

        var c = URLComponents(url: endpoint("/cas-sso/login", s.portal), resolvingAgainstBaseURL: true)!
        c.queryItems = [
            .init(name: "flowSessionId", value: s.sessionID),
            .init(name: "customPageId", value: s.params["customPageId"] ?? ""),
            .init(name: "preview", value: "false"),
            .init(name: "appType", value: "normal"),
            .init(name: "language", value: "zh-CN"),
            .init(name: "timer", value: String(Int(Date().timeIntervalSince1970 * 1000))),
            .init(name: "nasIp", value: s.params["nasIp"] ?? ""),
            .init(name: "userIp", value: s.params["userIp"] ?? ""),
            .init(name: "userMac", value: s.params["userMac"] ?? ""),
        ]
        let casURL = c.url!
        let page = try await http.get(casURL, headers: headers(s.url), follow: true).text
        guard let key = Self.pick(page, id: "login-croypto"),
              let execution = Self.pick(page, id: "login-page-flowkey") else {
            throw PortalError.failed("CAS 登录页里找不到密钥或令牌（页面结构可能变了）")
        }

        let form: [(String, String)] = [
            ("username", username),
            ("type", "UsernamePassword"),
            ("_eventId", "submit"),
            ("geolocation", ""),
            ("execution", execution),
            ("captcha_code", ""),
            ("croypto", key),
            ("password", try PortalCrypto.encrypt(keyBase64: key, text: password)),
            ("captcha_payload", try PortalCrypto.encrypt(keyBase64: key, text: "{}")),
        ]
        let postURL = URL(string: casURL.absoluteString + "&accept-language=zh-CN")!
        let r = try await http.postForm(postURL, form, headers: [
            "Origin": s.portal.absoluteString, "Referer": casURL.absoluteString, "isPortal": "true"])
        try Self.judgeCAS(r)
    }

    // MARK: 步骤 5

    /// 选运营商上线，返回门户里的运营商名字。
    public func selectService(_ s: PortalSession, carrier: Carrier) async throws -> String {
        var value = carrier.rawValue, name = carrier.displayName
        let list = try? await http.postJSON(endpoint("/eportal/network/serviceSelection", s.portal),
                                            ["sessionId": s.sessionID], headers: headers(s.url))
        let items = (list?.json()?["data"] as? [[String: Any]]) ?? []
        if !items.isEmpty {
            let entries = items.map { (name: Self.string($0, ["key", "name", "serviceName", "label"]),
                                       value: Self.string($0, ["value", "service", "serviceId", "id"])) }
            guard let hit = entries.first(where: { carrier.matches($0.value) || carrier.matches($0.name) }) else {
                throw PortalError.failed("门户的运营商列表里没有「\(carrier.displayName)」，可选：\(entries.map(\.name).joined(separator: "、"))")
            }
            value = hit.value; name = hit.name
        }

        let r = try await http.postJSON(endpoint("/eportal/network/serviceLogin", s.portal),
                                        ["sessionId": s.sessionID, "service": value], headers: headers(s.url))
        guard let body = r.json() else { throw PortalError.failed("serviceLogin 返回了非 JSON（HTTP \(r.status)）") }
        let data = body["data"] as? [String: Any] ?? [:]
        if data["authResult"] as? String == "success" { return name }
        let msg = (data["authMessage"] as? String) ?? (body["message"] as? String) ?? "HTTP \(r.status)"
        if ["密码", "不存在", "锁定", "停机", "欠费", "禁用"].contains(where: msg.contains) {
            throw PortalError.rejected(msg)
        }
        throw PortalError.failed("选择运营商「\(name)」后门户未放行：\(msg)")
    }

    // MARK: 下线

    public func logout() async throws {
        let s = try await openSession(captiveEntry: nil)
        let r = try await http.postJSON(endpoint("/eportal/network/offline", s.portal),
                                        ["sessionId": s.sessionID], headers: headers(s.url))
        let body = r.json() ?? [:]
        guard (body["code"] as? Int) == 200 else {
            throw PortalError.failed("下线失败：\((body["message"] as? String) ?? "HTTP \(r.status)")")
        }
    }

    // MARK: 解析

    static func judgeCAS(_ r: HTTPResponse) throws {
        let loc = r.location?.absoluteString ?? ""
        if r.isRedirect, loc.contains("ticket=ST-") || loc.contains("callbackAuthorize")
            || loc.contains("auth-success") || !loc.contains("/cas-sso/login") {
            return
        }
        for id in ["login-error-msg", "loginFailMessage"] {
            if let msg = pick(r.text, id: id) { throw PortalError.rejected(msg) }
        }
        if r.status == 401 || r.text.contains("login-croypto") { throw PortalError.rejected("账号或密码错误") }
        throw PortalError.failed("CAS 返回了无法识别的结果（HTTP \(r.status)）")
    }

    static func pick(_ html: String, id: String) -> String? {
        let pattern = #"id=["']\#(NSRegularExpression.escapedPattern(for: id))["'][^>]*>\s*([^<]+?)\s*<"#
        guard let re = try? NSRegularExpression(pattern: pattern),
              let m = re.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              let range = Range(m.range(at: 1), in: html) else { return nil }
        return String(html[range])
    }

    static func query(_ url: URL) -> [String: String] {
        var out: [String: String] = [:]
        for item in URLComponents(url: url, resolvingAgainstBaseURL: true)?.queryItems ?? [] {
            out[item.name] = item.value ?? ""
        }
        return out
    }

    static func origin(_ url: URL) -> URL? {
        guard let scheme = url.scheme, let host = url.host else { return nil }
        return URL(string: "\(scheme)://\(host)\(url.port.map { ":\($0)" } ?? "")")
    }

    static func string(_ dict: [String: Any], _ keys: [String]) -> String {
        for k in keys { if let v = dict[k], !"\(v)".isEmpty { return "\(v)" } }
        return ""
    }
}
