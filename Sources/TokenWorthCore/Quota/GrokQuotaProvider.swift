import Foundation

public struct GrokQuotaProvider: QuotaProvider {
    public let provider: ProviderID = .grok
    private let transport: any HTTPTransport
    private let endpointURL = URL(string: "https://cli-chat-proxy.grok.com/v1/billing")!

    public init(transport: any HTTPTransport = URLSessionTransport()) {
        self.transport = transport
    }

    public func fetchQuota(for account: AccountProfile, settings: AppSettings) async -> AccountQuotaSnapshot {
        if let external = ExternalQuotaBridge.fetchIfConfigured(for: account) {
            return external
        }

        guard let token = resolveToken(for: account) else {
            return AccountQuotaSnapshot(
                accountID: account.id,
                provider: .grok,
                planName: account.planName,
                status: .notConfigured("No ~/.grok/auth.json found (local logs still tracked)")
            )
        }

        var request = URLRequest(url: endpointURL)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let response = try await transport.send(request)
            if response.statusCode == 401 || response.statusCode == 403 {
                return AccountQuotaSnapshot(
                    accountID: account.id,
                    provider: .grok,
                    planName: account.planName,
                    status: .error("Grok auth expired or unauthorized (HTTP \(response.statusCode))")
                )
            }
            if response.statusCode == 429 {
                return AccountQuotaSnapshot(
                    accountID: account.id,
                    provider: .grok,
                    planName: account.planName,
                    status: .error("HTTP 429 rate limited")
                )
            }
            guard (200..<300).contains(response.statusCode) else {
                return AccountQuotaSnapshot(
                    accountID: account.id,
                    provider: .grok,
                    planName: account.planName,
                    status: .error("HTTP \(response.statusCode)")
                )
            }
            return try Self.decodeGrokBilling(data: response.data, account: account)
        } catch {
            return AccountQuotaSnapshot(
                accountID: account.id,
                provider: .grok,
                planName: account.planName,
                status: .error(error.localizedDescription)
            )
        }
    }

    private func resolveToken(for account: AccountProfile) -> String? {
        var paths: [String] = []
        if let cred = account.credentialPath?.trimmingCharacters(in: .whitespacesAndNewlines), !cred.isEmpty {
            paths.append(cred)
        }
        if let logDir = account.customLogDirectory?.trimmingCharacters(in: .whitespacesAndNewlines), !logDir.isEmpty {
            let expanded = AppPaths.expandTilde(logDir)
            paths.append((expanded as NSString).appendingPathComponent("auth.json"))
        }
        paths.append("~/.grok/auth.json")

        for path in paths {
            guard let root = QuotaJSONHelpers.readJSONDictionary(at: path) else { continue }
            if let oauth = root["oauth"] as? [String: Any],
               let token = QuotaJSONHelpers.stringValue(oauth["access_token"])
                ?? QuotaJSONHelpers.stringValue(oauth["accessToken"]) {
                return token
            }
            if let token = QuotaJSONHelpers.stringValue(root["access_token"])
                ?? QuotaJSONHelpers.stringValue(root["accessToken"])
                ?? QuotaJSONHelpers.stringValue(root["bearer_token"])
                ?? QuotaJSONHelpers.stringValue(root["token"])
                ?? QuotaJSONHelpers.stringValue(root["session_token"]) {
                return token
            }
        }
        return nil
    }

    public static func decodeGrokBilling(
        data: Data,
        account: AccountProfile,
        fetchedAt: Date = Date()
    ) throws -> AccountQuotaSnapshot {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw QuotaProviderError.decodingFailed("Expected JSON object")
        }

        let plan = QuotaJSONHelpers.stringValue(root["plan_name"])
            ?? QuotaJSONHelpers.stringValue(root["plan"])
            ?? QuotaJSONHelpers.stringValue(root["tier"])
            ?? account.planName

        var windows: [QuotaWindow] = []

        if let weekly = parseFlexibleWindow(
            root["weekly_limit"] as? [String: Any] ?? root["seven_day"] as? [String: Any],
            id: "grok-7d",
            label: "7d",
            duration: 7 * 24 * 3600
        ) {
            windows.append(weekly)
        }

        if let session = parseFlexibleWindow(
            root["session_limit"] as? [String: Any] ?? root["five_hour"] as? [String: Any] ?? root["rolling_window"] as? [String: Any],
            id: "grok-5h",
            label: "5h",
            duration: 5 * 3600
        ) {
            windows.append(session)
        }

        if let rawWindows = root["windows"] as? [[String: Any]] {
            for (idx, item) in rawWindows.enumerated() {
                let label = QuotaJSONHelpers.stringValue(item["label"]) ?? "w\(idx)"
                let dur = QuotaJSONHelpers.doubleValue(item["duration_seconds"]) ?? (label.contains("7") ? 7 * 24 * 3600 : 5 * 3600)
                if let win = parseFlexibleWindow(item, id: "grok-w-\(idx)", label: label, duration: dur) {
                    windows.append(win)
                }
            }
        }

        var creditsUsedUSD: Double?
        var creditsLimitUSD: Double?
        if let credits = root["credits"] as? [String: Any] {
            let used = QuotaJSONHelpers.doubleValue(credits["used_usd"]) ?? QuotaJSONHelpers.doubleValue(credits["used"])
            let limit = QuotaJSONHelpers.doubleValue(credits["limit_usd"]) ?? QuotaJSONHelpers.doubleValue(credits["limit"])
            let remaining = QuotaJSONHelpers.doubleValue(credits["remaining_usd"]) ?? QuotaJSONHelpers.doubleValue(credits["remaining"])
            creditsUsedUSD = used
            creditsLimitUSD = limit
            if windows.isEmpty, let used, let limit, limit > 0 {
                let pct = (used / limit) * 100.0
                windows.append(
                    QuotaWindow(
                        id: "grok-credits",
                        label: "Credits",
                        durationSeconds: 7 * 24 * 3600,
                        usedPercent: pct,
                        resetsAt: QuotaJSONHelpers.parseDate(credits["resets_at"] ?? credits["reset_at"])
                    )
                )
            } else if windows.isEmpty, let remaining, let limit, limit > 0 {
                let pct = ((limit - remaining) / limit) * 100.0
                windows.append(
                    QuotaWindow(
                        id: "grok-credits",
                        label: "Credits",
                        durationSeconds: 7 * 24 * 3600,
                        usedPercent: pct,
                        resetsAt: QuotaJSONHelpers.parseDate(credits["resets_at"] ?? credits["reset_at"])
                    )
                )
            }
        }

        let groups = windows.isEmpty ? [] : [QuotaGroup(id: "grok-quota", title: "Grok Build & Subscription", windows: windows)]

        return AccountQuotaSnapshot(
            accountID: account.id,
            provider: .grok,
            planName: plan,
            groups: groups,
            extraUsageUSD: creditsUsedUSD,
            extraUsageLimitUSD: creditsLimitUSD,
            fetchedAt: fetchedAt,
            status: .live
        )
    }

    private static func parseFlexibleWindow(
        _ dict: [String: Any]?,
        id: String,
        label: String,
        duration: TimeInterval
    ) -> QuotaWindow? {
        guard let dict else { return nil }
        let percent: Double?
        if let direct = QuotaJSONHelpers.doubleValue(dict["used_percent"])
            ?? QuotaJSONHelpers.doubleValue(dict["utilization"]) {
            percent = direct
        } else if let used = QuotaJSONHelpers.doubleValue(dict["used"]),
                  let limit = QuotaJSONHelpers.doubleValue(dict["limit"]),
                  limit > 0 {
            percent = (used / limit) * 100.0
        } else {
            percent = nil
        }
        guard let percent else { return nil }

        let resetsAt = QuotaJSONHelpers.parseDate(dict["resets_at"] ?? dict["reset_at"])
        return QuotaWindow(
            id: id,
            label: label,
            durationSeconds: QuotaJSONHelpers.doubleValue(dict["duration_seconds"]) ?? duration,
            usedPercent: percent,
            resetsAt: resetsAt
        )
    }
}
