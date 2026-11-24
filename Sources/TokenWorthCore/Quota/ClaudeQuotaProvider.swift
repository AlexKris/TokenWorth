import Foundation

public struct ClaudeQuotaProvider: QuotaProvider {
    public let provider: ProviderID = .claude
    private let transport: any HTTPTransport
    private let endpointURL = URL(string: "https://api.anthropic.com/api/oauth/usage")!

    public init(transport: any HTTPTransport = URLSessionTransport()) {
        self.transport = transport
    }

    public func fetchQuota(for account: AccountProfile, settings: AppSettings) async -> AccountQuotaSnapshot {
        if let external = ExternalQuotaBridge.fetchIfConfigured(for: account) {
            return external
        }

        guard let token = resolveOAuthToken(for: account, allowKeychain: settings.allowKeychainReads) else {
            return AccountQuotaSnapshot(
                accountID: account.id,
                provider: .claude,
                planName: account.planName,
                status: .notConfigured("No ~/.claude/.credentials.json found (enable Keychain read in Settings if stored in Keychain)")
            )
        }

        var request = URLRequest(url: endpointURL)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let response = try await transport.send(request)
            if response.statusCode == 401 || response.statusCode == 403 {
                return AccountQuotaSnapshot(
                    accountID: account.id,
                    provider: .claude,
                    planName: account.planName,
                    status: .error("OAuth token expired or unauthorized (HTTP \(response.statusCode))")
                )
            }
            if response.statusCode == 429 {
                return AccountQuotaSnapshot(
                    accountID: account.id,
                    provider: .claude,
                    planName: account.planName,
                    status: .error("HTTP 429 rate limited")
                )
            }
            guard (200..<300).contains(response.statusCode) else {
                return AccountQuotaSnapshot(
                    accountID: account.id,
                    provider: .claude,
                    planName: account.planName,
                    status: .error("HTTP \(response.statusCode)")
                )
            }
            return try Self.decodeClaudeUsage(data: response.data, account: account)
        } catch {
            return AccountQuotaSnapshot(
                accountID: account.id,
                provider: .claude,
                planName: account.planName,
                status: .error(error.localizedDescription)
            )
        }
    }

    private func resolveOAuthToken(for account: AccountProfile, allowKeychain: Bool) -> String? {
        var candidatePaths: [String] = []
        if let credPath = account.credentialPath?.trimmingCharacters(in: .whitespacesAndNewlines), !credPath.isEmpty {
            candidatePaths.append(credPath)
        }
        if let logDir = account.customLogDirectory?.trimmingCharacters(in: .whitespacesAndNewlines), !logDir.isEmpty {
            let expanded = AppPaths.expandTilde(logDir)
            candidatePaths.append((expanded as NSString).appendingPathComponent(".credentials.json"))
        }
        candidatePaths.append("~/.claude/.credentials.json")

        for path in candidatePaths {
            if let obj = QuotaJSONHelpers.readJSONDictionary(at: path),
               let token = Self.extractToken(from: obj) {
                return token
            }
        }

        if allowKeychain, let data = KeychainReader.readGenericPassword(service: "Claude Code-credentials") {
            if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let token = Self.extractToken(from: obj) {
                return token
            }
            if let raw = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
               !raw.isEmpty, !raw.hasPrefix("{") {
                return raw
            }
        }

        return nil
    }

    private static func extractToken(from dict: [String: Any]) -> String? {
        if let claudeOAuth = dict["claudeAiOauth"] as? [String: Any],
           let token = QuotaJSONHelpers.stringValue(claudeOAuth["accessToken"])
            ?? QuotaJSONHelpers.stringValue(claudeOAuth["access_token"]) {
            return token
        }
        if let oauth = dict["oauth"] as? [String: Any],
           let token = QuotaJSONHelpers.stringValue(oauth["accessToken"])
            ?? QuotaJSONHelpers.stringValue(oauth["access_token"]) {
            return token
        }
        return QuotaJSONHelpers.stringValue(dict["accessToken"])
            ?? QuotaJSONHelpers.stringValue(dict["access_token"])
    }

    public static func decodeClaudeUsage(
        data: Data,
        account: AccountProfile,
        fetchedAt: Date = Date()
    ) throws -> AccountQuotaSnapshot {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw QuotaProviderError.decodingFailed("Expected JSON object")
        }

        var primaryWindows: [QuotaWindow] = []
        if let sevenDay = parseWindow(dict: root["seven_day"] as? [String: Any], id: "7d", label: "7d", duration: 7 * 24 * 3600) {
            primaryWindows.append(sevenDay)
        }
        if let fiveHour = parseWindow(dict: root["five_hour"] as? [String: Any], id: "5h", label: "5h", duration: 5 * 3600) {
            primaryWindows.append(fiveHour)
        }

        var modelWindows: [QuotaWindow] = []
        if let sonnet = parseWindow(dict: root["seven_day_sonnet"] as? [String: Any], id: "7d-sonnet", label: "Sonnet 7d", duration: 7 * 24 * 3600) {
            modelWindows.append(sonnet)
        }
        if let opus = parseWindow(dict: root["seven_day_opus"] as? [String: Any], id: "7d-opus", label: "Opus 7d", duration: 7 * 24 * 3600) {
            modelWindows.append(opus)
        }

        var groups: [QuotaGroup] = []
        if !primaryWindows.isEmpty {
            groups.append(QuotaGroup(id: "all-models", title: "All Claude Models", windows: primaryWindows))
        }
        if !modelWindows.isEmpty {
            groups.append(QuotaGroup(id: "model-specific", title: "Model Windows", windows: modelWindows))
        }

        var extraUsedUSD: Double?
        var extraLimitUSD: Double?
        if let extra = root["extra_usage"] as? [String: Any],
           (extra["is_enabled"] as? Bool) ?? true {
            if let usedCents = QuotaJSONHelpers.doubleValue(extra["used_credits"]) {
                extraUsedUSD = usedCents / 100.0
            }
            if let limitCents = QuotaJSONHelpers.doubleValue(extra["monthly_limit"]) {
                extraLimitUSD = limitCents / 100.0
            }
        }

        return AccountQuotaSnapshot(
            accountID: account.id,
            provider: .claude,
            planName: account.planName,
            groups: groups,
            extraUsageUSD: extraUsedUSD,
            extraUsageLimitUSD: extraLimitUSD,
            fetchedAt: fetchedAt,
            status: .live
        )
    }

    private static func parseWindow(
        dict: [String: Any]?,
        id: String,
        label: String,
        duration: TimeInterval
    ) -> QuotaWindow? {
        guard let dict, let rawUtil = QuotaJSONHelpers.doubleValue(dict["utilization"]) else {
            return nil
        }
        let resetsAt = QuotaJSONHelpers.parseDate(dict["resets_at"])
        return QuotaWindow(
            id: id,
            label: label,
            durationSeconds: duration,
            usedPercent: rawUtil,
            resetsAt: resetsAt
        )
    }
}
