import Foundation
import Testing
@testable import CUITNetCore

@Test func aesMatchesCapturedPortalCiphertext() throws {
    // 浏览器在真实门户上加密 zzprobe0001 得到的密文
    #expect(try PortalCrypto.encrypt(keyBase64: "Qvy2L55c2aTCHUc6uX/Llw==", text: "zzprobe0001") == "Uz/UJgU3BdOiWO9Bfrykrg==")
}

@Test func formEncodingEscapesBase64() {
    #expect(HTTPClient.formEncode("a+b/c=") == "a%2Bb%2Fc%3D")
}

@Test func carrierAliases() {
    #expect(Carrier.cmcc.matches("中国移动"))
    #expect(Carrier.ctcc.matches("CTCC"))
    #expect(!Carrier.unicom.matches("移动"))
}

/// 启动 testing/fake_portal.py 作为假门户，端到端跑完整链路。
final class FakePortal: @unchecked Sendable {
    let process = Process()
    let base: URL

    init() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        let port = Int.random(in: 20000..<40000)
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["python3", root.appendingPathComponent("testing/fake_portal.py").path, String(port)]
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        let line = String(decoding: pipe.fileHandleForReading.availableData, as: UTF8.self)
        base = URL(string: line.trimmingCharacters(in: .whitespacesAndNewlines))!
    }

    var probes: [Probe] { [Probe(base.absoluteString + "/generate_204", status: 204)] }

    func state() async throws -> [String: Any] {
        let r = try await HTTPClient().postJSON(base.appendingPathComponent("__state"), [:])
        return r.json() ?? [:]
    }

    deinit { process.terminate() }
}

@Suite(.serialized) struct EndToEnd {
    let portal: FakePortal
    init() throws { portal = try FakePortal() }

    @Test func detectsCaptivePortal() async throws {
        let state = await Connectivity.check(HTTPClient(), probes: portal.probes)
        guard case .captive(let entry) = state else { Issue.record("应为 captive，实际 \(state)"); return }
        #expect(entry?.path == "/eportal/index.jsp")
    }

    @Test func loginEndToEnd() async throws {
        let out = try await performLogin(Credentials(username: "2023000001", password: "right-pass", carrier: .cmcc),
                                         portal: portal.base, probes: portal.probes)
        #expect(out.message == "登录成功（移动）")
        #expect(out.learnedNAS == "10.254.0.1")
        let s = try await portal.state()
        #expect(s["online"] as? Bool == true)
        #expect(s["chosen"] as? String == "cmcc")
        #expect(await Connectivity.check(HTTPClient(), probes: portal.probes) == .online)

        try await PortalClient(portal: portal.base).logout()
        #expect(try await portal.state()["online"] as? Bool == false)
    }

    @Test func wrongPasswordIsRejected() async throws {
        do {
            _ = try await performLogin(Credentials(username: "2023000001", password: "wrong", carrier: .cmcc),
                                       portal: portal.base, probes: portal.probes)
            Issue.record("应当被拒")
        } catch let e as PortalError {
            #expect(e.isRejected)
            #expect(e.localizedDescription.contains("密码错误"))
        }
    }
}
