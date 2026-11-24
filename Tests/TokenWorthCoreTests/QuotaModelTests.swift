import Foundation
import Testing
@testable import TokenWorthCore

private struct MockTransport: HTTPTransport {
    let handler: @Sendable (URLRequest) async throws -> HTTPResponse

    func send(_ request: URLRequest) async throws -> HTTPResponse {
        try await handler(request)
    }
}

@Suite("Quota Models & Provider Decoders")
struct QuotaModelTests {
    @Test("QuotaWindow computes pacePercent and resetSummary accurately")
    func paceAndResetSummary() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 8 * 3600)!

        let now = ISO8601DateFormatter().date(from: "2026-11-24T09:09:00+08:00")!
        let resetsSevenDays = now.addingTimeInterval(6 * 86400 + 23 * 3600 + 300) // 6d 23h 5m left in 7d window
        let window7d = QuotaWindow(id: "7d", label: "7d", durationSeconds: 7 * 86400, usedPercent: 1, resetsAt: resetsSevenDays)

        let pace7d = window7d.pacePercent(at: now)!
        #expect(pace7d > 0 && pace7d < 2)
        #expect(window7d.resetSummary(at: now, calendar: calendar) == "resets 6d 23h · Dec 1 08:14")

        let midpointReset = now.addingTimeInterval(2.5 * 3600)
        let window5h = QuotaWindow(id: "5h", label: "5h", durationSeconds: 5 * 3600, usedPercent: 30, resetsAt: midpointReset)
        #expect(abs((window5h.pacePercent(at: now) ?? 0) - 50.0) < 0.01)
    }

    @Test("AccountProfile masks emails in screenshot format")
    func emailMasking() {
        let acct = AccountProfile(provider: .antigravity, displayName: "Ultra", email: "tokenworth@gmail.com", planName: "Google AI Ultra")
        #expect(acct.maskedEmailDisplay(masked: true) == "t•••••@g••••••")
        #expect(acct.maskedEmailDisplay(masked: false) == "tokenworth@gmail.com")
    }

    @Test("Decodes Claude, Codex, Grok, and Antigravity quota payloads")
    func providerPayloadDecoding() throws {
        let claudeAcct = AccountProfile(id: "c1", provider: .claude, displayName: "Claude", planName: "Claude Max")
        let claudeJSON = """
        {
          "five_hour": {"utilization": 18.5, "resets_at": "2026-11-24T14:00:00Z"},
          "seven_day": {"utilization": 42.0, "resets_at": "2026-11-29T00:00:00Z"},
          "extra_usage": {"is_enabled": true, "monthly_limit": 10000, "used_credits": 1450}
        }
        """.data(using: .utf8)!
        let claudeSnap = try ClaudeQuotaProvider.decodeClaudeUsage(data: claudeJSON, account: claudeAcct)
        #expect(claudeSnap.groups.count == 1)
        #expect(claudeSnap.groups[0].windows.count == 2)
        #expect(claudeSnap.extraUsageUSD == 14.5)
        #expect(claudeSnap.extraUsageLimitUSD == 100.0)

        let codexAcct = AccountProfile(id: "x1", provider: .codex, displayName: "Codex", planName: "ChatGPT Pro")
        let codexJSON = """
        {
          "plan_type": "pro",
          "rate_limit": {
            "primary_window": {"used_percent": 12, "limit_window_seconds": 18000, "reset_at": 1795498800},
            "secondary_window": {"used_percent": 31, "limit_window_seconds": 604800, "reset_at": 1795900000}
          },
          "credits": {"balance": 48.25}
        }
        """.data(using: .utf8)!
        let codexSnap = try CodexQuotaProvider.decodeCodexUsage(data: codexJSON, account: codexAcct)
        #expect(codexSnap.planName == "Pro")
        #expect(codexSnap.groups[0].windows.count == 2)
        #expect(codexSnap.extraUsageUSD == 48.25)

        let grokAcct = AccountProfile(id: "g1", provider: .grok, displayName: "Grok", planName: "SuperGrok")
        let grokJSON = """
        {
          "plan": "SuperGrok",
          "weekly_limit": {"used": 24, "limit": 100, "resets_at": "2026-11-30T00:00:00Z"},
          "session_limit": {"used_percent": 9, "resets_at": "2026-11-24T15:00:00Z"}
        }
        """.data(using: .utf8)!
        let grokSnap = try GrokQuotaProvider.decodeGrokBilling(data: grokJSON, account: grokAcct)
        #expect(grokSnap.groups[0].windows.count == 2)
        #expect(grokSnap.groups[0].windows[0].usedPercent == 24)

        let agAcct = AccountProfile(id: "a1", provider: .antigravity, displayName: "AG", email: "tokenworth@gmail.com", planName: "Google AI Ultra")
        let agJSON = """
        {
          "accounts": [
            {
              "accountID": "a1",
              "planName": "Google AI Ultra",
              "groups": [
                {"title": "Gemini Models", "windows": [{"label": "7d", "usedPercent": 1}, {"label": "5h", "usedPercent": 2}]}
              ]
            }
          ]
        }
        """.data(using: .utf8)!
        let agSnap = AntigravityQuotaProvider.decodeAntigravityJSON(data: agJSON, account: agAcct)
        #expect(agSnap.status == .live)
        #expect(agSnap.groups[0].windows[1].usedPercent == 2)
    }

    @Test("QuotaPollingEngine falls back to cached snapshot on HTTP 429")
    func pollingEngine429StaleWhileRevalidate() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("QuotaPollTest-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let credFile = dir.appendingPathComponent(".credentials.json")
        try #"{"claudeAiOauth":{"accessToken":"tok_123"}}"#.write(to: credFile, atomically: true, encoding: .utf8)

        let counter = LockBox(0)
        let transport = MockTransport { _ in
            let n = counter.next()
            if n == 1 {
                let ok = #"{"five_hour":{"utilization":25.0,"resets_at":"2026-11-24T15:00:00Z"}}"#.data(using: .utf8)!
                return HTTPResponse(statusCode: 200, data: ok)
            }
            return HTTPResponse(statusCode: 429, data: Data())
        }

        let account = AccountProfile(
            id: "c-poll",
            provider: .claude,
            displayName: "Claude",
            planName: "Claude Max",
            credentialPath: credFile.path
        )
        let engine = QuotaPollingEngine(providers: [ClaudeQuotaProvider(transport: transport)])
        let settings = AppSettings(accounts: [account])

        let first = await engine.refreshAll(accounts: [account], settings: settings, force: true)
        #expect(first["c-poll"]?.status == .live)
        #expect(first["c-poll"]?.groups.first?.windows.first?.usedPercent == 25.0)

        let second = await engine.refreshAll(accounts: [account], settings: settings, force: true)
        #expect(second["c-poll"]?.status == .cached)
        #expect(second["c-poll"]?.groups.first?.windows.first?.usedPercent == 25.0)
    }
}

private final class LockBox: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Int
    init(_ initial: Int) { self.value = initial }
    func next() -> Int {
        lock.lock()
        defer { lock.unlock() }
        value += 1
        return value
    }
}
