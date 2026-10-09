import Foundation

public struct HTTPResponse: Sendable {
    public let status: Int
    public let url: URL
    public let headers: [String: String]
    public let body: Data

    public var text: String { String(decoding: body, as: UTF8.self) }

    /// 解析成绝对地址的 Location 头。
    public var location: URL? {
        guard let raw = headers["location"], !raw.isEmpty else { return nil }
        return URL(string: raw, relativeTo: url)?.absoluteURL
    }

    public var isRedirect: Bool { [301, 302, 303, 307, 308].contains(status) }

    public func json() -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: body)) as? [String: Any]
    }
}

/// 不自动跳转、不走系统代理、自带 Cookie 的 HTTP 客户端。
///
/// 认证请求必须直连：开着代理时请求从代理出口发出，网关看不到本机，登录必然失败。
public final class HTTPClient: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    public static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0 Safari/537.36"

    private let session: URLSession
    public let timeout: TimeInterval

    public init(timeout: TimeInterval = 8) {
        self.timeout = timeout
        let config = URLSessionConfiguration.ephemeral
        config.connectionProxyDictionary = [
            kCFNetworkProxiesHTTPEnable as String: false,
            kCFNetworkProxiesHTTPSEnable as String: false,
            kCFNetworkProxiesSOCKSEnable as String: false,
            kCFNetworkProxiesProxyAutoConfigEnable as String: false,
            kCFNetworkProxiesProxyAutoDiscoveryEnable as String: false,
        ]
        config.httpShouldSetCookies = true
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.urlCache = nil
        session = URLSession(configuration: config)
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask,
                           willPerformHTTPRedirection response: HTTPURLResponse,
                           newRequest request: URLRequest) async -> URLRequest? {
        nil
    }

    public func get(_ url: URL, headers: [String: String] = [:], follow: Bool = false,
                    timeout: TimeInterval? = nil) async throws -> HTTPResponse {
        try await send(method: "GET", url: url, body: nil, headers: headers, follow: follow, timeout: timeout)
    }

    public func postForm(_ url: URL, _ form: [(String, String)], headers: [String: String] = [:]) async throws -> HTTPResponse {
        var h = headers
        h["Content-Type"] = "application/x-www-form-urlencoded"
        let body = form.map { "\(Self.formEncode($0.0))=\(Self.formEncode($0.1))" }.joined(separator: "&")
        return try await send(method: "POST", url: url, body: Data(body.utf8), headers: h, follow: false, timeout: nil)
    }

    public func postJSON(_ url: URL, _ object: [String: Any], headers: [String: String] = [:]) async throws -> HTTPResponse {
        var h = headers
        h["Content-Type"] = "application/json;charset=UTF-8"
        let body = try JSONSerialization.data(withJSONObject: object)
        return try await send(method: "POST", url: url, body: body, headers: h, follow: false, timeout: nil)
    }

    private func send(method: String, url: URL, body: Data?, headers: [String: String],
                      follow: Bool, timeout: TimeInterval?) async throws -> HTTPResponse {
        var url = url, method = method, body = body
        for _ in 0..<10 {
            var req = URLRequest(url: url, timeoutInterval: timeout ?? self.timeout)
            req.httpMethod = method
            req.httpBody = body
            req.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
            req.setValue("zh-CN,zh;q=0.9", forHTTPHeaderField: "Accept-Language")
            for (k, v) in headers where !(body == nil && k == "Content-Type") {
                req.setValue(v, forHTTPHeaderField: k)
            }
            let (data, raw) = try await session.data(for: req, delegate: self)
            guard let http = raw as? HTTPURLResponse else { throw URLError(.badServerResponse) }
            var hdrs: [String: String] = [:]
            for (k, v) in http.allHeaderFields { hdrs[String(describing: k).lowercased()] = String(describing: v) }
            let resp = HTTPResponse(status: http.statusCode, url: url, headers: hdrs, body: data)
            guard follow, resp.isRedirect, let next = resp.location else { return resp }
            url = next; method = "GET"; body = nil
        }
        throw PortalError.unexpected("跳转次数过多")
    }

    /// application/x-www-form-urlencoded 编码（Base64 里的 + / = 必须转义）。
    static func formEncode(_ s: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._*")
        return (s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s)
    }
}
