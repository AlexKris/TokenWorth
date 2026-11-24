import Foundation

public struct CodexQuotaProvider: QuotaProvider {
    public let provider: ProviderID = .codex
    private let transport: any HTTPTransport
    private let endpointURL = URL(string: "https://chatgpt.com/backend-api/wham/usage")!

    public init(transport: any HTTPTransport = URLSessionTransport()) {
        self.transport = transport
    }

    public func fetchQuota(for account: AccountProfile, settings: AppSettings) async -> AccountQuotaSnapshot {
        if let external = ExternalQuotaBridge.fetchIfConfigured(for: account) {
            return external
        }

        guard let creds = resolveCredentials(for: account) else {
            return AccountQuotaSnapshot(
                accountID: account.id,
                provider: .codex,
                planName: account.planName,
                status: .notConfigured("No ~/.codex/auth.json found")
            )
        }

        var request = URLRequest(url: endpointURL)
        request.httpMethod = "GET"
        request.setValue("Bearer \(creds.accessToken)", forHTTPHeaderField: "Authorization")
        if let accountID = creds.accountID {
            request.setValue(accountID, forHTTPHeaderField: "ChatGPT-Account-Id")
        }
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let response = try await transport.send(request)
            if response.statusCode == 401 || response.statusCode == 403 {
                return AccountQuotaSnapshot(
                    accountID: account.id,
                    provider: .codex,
                    planName: account.planName,
                    status: .error("Codex auth expired (HTTP \(response.statusCode))")
                )
            }
            if response.statusCode == 429 {
                return AccountQuotaSnapshot(
                    accountID: account.id,
                    provider: .codex,
                    planName: account.planName,
                    status: .error("HTTP 429 rate limited")
                )
            }
            guard (200..<300).contains(response.statusCode) else {
                return AccountQuotaSnapshot(
                    accountID: account.id,
                    provider: .codex,
                    planName: account.planName,
                    status: .error("HTTP \(response.statusCode)")
                )
            }
            return try Self.decodeCodexUsage(data: response.data, account: account)
        } catch {
            return AccountQuotaSnapshot(
                accountID: account.id,
                provider: .codex,
                planName: account.planName,
                status: .error(error.localizedDescription)
            )
        }
    }

    private struct CodexCredentials {
        let accessToken: String
        let accountID: String?
    }

    private func resolveCredentials(for account: AccountProfile) -> CodexCredentials? {
        var paths: [String] = []
        if let cred = account.credentialPath?.trimmingCharacters(in: .whitespacesAndNewlines), !cred.isEmpty {
            paths.append(cred)
        }
        if let logDir = account.customLogDirectory?.trimmingCharacters(in: .whitespacesAndNewlines), !logDir.isEmpty {
            let expanded = AppPaths.expandTilde(logDir)
            paths.append((expanded as NSString).appendingPathComponent("auth.json"))
        }
        paths.append("~/.codex/auth.json")

        for path in paths {
            guard let root = QuotaJSONHelpers.readJSONDictionary(at: path) else { continue }
            let tokens = root["tokens"] as? [String: Any]
            let accessToken = QuotaJSONHelpers.stringValue(tokens?["access_token"])
                ?? QuotaJSONHelpers.stringValue(root["access_token"])
                ?? QuotaJSONHelpers.stringValue(root["OPENAI_API_KEY"])
            if let accessToken {
                let accountID = QuotaJSONHelpers.stringValue(tokens?["account_id"])
                    ?? QuotaJSONHelpers.stringValue(root["account_id"])
                return CodexCredentials(accessToken: accessToken, accountID: accountID)
            }
        }
        return nil
    }

    public static func decodeCodexUsage(
        data: Data,
        account: AccountProfile,
        fetchedAt: Date = Date()
    ) throws -> AccountQuotaSnapshot {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw QuotaProviderError.decodingFailed("Expected JSON object")
        }

        let planType = QuotaJSONHelpers.stringValue(root["plan_type"])?.capitalized
        var groups: [QuotaGroup] = []

        if let rateLimit = root["rate_limit"] as? [String: Any] {
            var windows: [QuotaWindow] = []
            if let secondary = parseRateWindow(rateLimit["secondary_window"] as? [String: Any], defaultID: "7d", defaultLabel: "7d", defaultDuration: 7 * 24 * 3600) {
                windows.append(secondary)
            }
            if let primary = parseRateWindow(rateLimit["primary_window"] as? [String: Any], defaultID: "5h", defaultLabel: "5h", defaultDuration: 5 * 3600) {
                windows.append(primary)
            }
            if !windows.isEmpty {
                groups.append(QuotaGroup(id: "codex-rate-limit", title: "Codex Limits", windows: windows))
            }
        }

        if let reviewLimit = root["code_review_rate_limit"] as? [String: Any] {
            var reviewWindows: [QuotaWindow] = []
            if let primary = parseRateWindow(reviewLimit["primary_window"] as? [String: Any], defaultID: "review-primary", defaultLabel: "Review", defaultDuration: 7 * 24 * 3600) {
                reviewWindows.append(primary)
            }
            if !reviewWindows.isEmpty {
                groups.append(QuotaGroup(id: "codex-review", title: "Code Review", windows: reviewWindows))
            }
        }

        var extraBalance: Double?
        if let credits = root["credits"] as? [String: Any] {
            extraBalance = QuotaJSONHelpers.doubleValue(credits["balance"])
        }

        return AccountQuotaSnapshot(
            accountID: account.id,
            provider: .codex,
            planName: planType ?? account.planName,
            groups: groups,
            extraUsageUSD: extraBalance,
            extraUsageLimitUSD: nil,
            fetchedAt: fetchedAt,
            status: .live
        )
    }

    private static func parseRateWindow(
        _ dict: [String: Any]?,
        defaultID: String,
        defaultLabel: String,
        defaultDuration: TimeInterval
    ) -> QuotaWindow? {
        guard let dict, let usedPercent = QuotaJSONHelpers.doubleValue(dict["used_percent"]) else {
            return nil
        }
        let duration = QuotaJSONHelpers.doubleValue(dict["limit_window_seconds"]) ?? defaultDuration
        let label = formatDurationLabel(duration, fallback: defaultLabel)
        let resetDate = QuotaJSONHelpers.parseDate(dict["reset_at"])
        return QuotaWindow(
            id: "\(defaultID)-\(Int(duration))",
            label: label,
            durationSeconds: duration,
            usedPercent: usedPercent,
            resetsAt: resetDate
        )
    }

    private static func formatDurationLabel(_ seconds: TimeInterval, fallback: String) -> String {
        let hours = Int(round(seconds / 3600.0))
        if hours >= 24 && hours % 24 == 0 {
            return "\(hours / 24)d"
        }
        if hours > 0 {
            return "\(hours)h"
        }
        return fallback
    }
}
