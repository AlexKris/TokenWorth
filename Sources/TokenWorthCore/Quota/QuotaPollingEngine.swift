import Foundation

public actor QuotaPollingEngine {
    private struct CacheRecord {
        var snapshot: AccountQuotaSnapshot
        var rateLimitHits: Int
        var cooldownUntil: Date?
    }

    private let providersByID: [ProviderID: any QuotaProvider]
    private var cache: [String: CacheRecord] = [:]

    public init(providers: [any QuotaProvider] = QuotaPollingEngine.defaultProviders()) {
        var map: [ProviderID: any QuotaProvider] = [:]
        for provider in providers {
            map[provider.provider] = provider
        }
        self.providersByID = map
    }

    public static func defaultProviders(transport: any HTTPTransport = URLSessionTransport()) -> [any QuotaProvider] {
        [
            ClaudeQuotaProvider(transport: transport),
            CodexQuotaProvider(transport: transport),
            GrokQuotaProvider(transport: transport),
            AntigravityQuotaProvider()
        ]
    }

    public func refreshAll(
        accounts: [AccountProfile],
        settings: AppSettings,
        force: Bool = false,
        now: Date = Date()
    ) async -> [String: AccountQuotaSnapshot] {
        if settings.useDemoData {
            let demoSnapshots = DemoDataFactory.demoQuotaSnapshots(for: accounts, now: now)
            return demoSnapshots
        }

        var results: [String: AccountQuotaSnapshot] = [:]
        var accountsToFetch: [AccountProfile] = []

        for account in accounts {
            if !force, let record = cache[account.id], let cooldown = record.cooldownUntil, now < cooldown {
                var stale = record.snapshot
                stale.status = .cached
                results[account.id] = stale
            } else {
                accountsToFetch.append(account)
            }
        }

        let providersSnapshot = providersByID
        let fetchedPairs = await withTaskGroup(of: (String, AccountQuotaSnapshot).self) { group in
            for account in accountsToFetch {
                guard let provider = providersSnapshot[account.provider] else { continue }
                group.addTask {
                    let snap = await provider.fetchQuota(for: account, settings: settings)
                    return (account.id, snap)
                }
            }
            var pairs: [(String, AccountQuotaSnapshot)] = []
            for await pair in group {
                pairs.append(pair)
            }
            return pairs
        }

        for (accountID, snapshot) in fetchedPairs {
            switch snapshot.status {
            case .live, .demo:
                cache[accountID] = CacheRecord(snapshot: snapshot, rateLimitHits: 0, cooldownUntil: nil)
                results[accountID] = snapshot
            case .error(let message):
                let is429 = message.contains("429")
                if var existing = cache[accountID], existing.snapshot.status.isHealthy {
                    let hits = is429 ? existing.rateLimitHits + 1 : existing.rateLimitHits
                    let backoffSeconds = is429 ? min(3600.0, 60.0 * pow(2.0, Double(hits - 1))) : 60.0
                    existing.rateLimitHits = hits
                    existing.cooldownUntil = now.addingTimeInterval(backoffSeconds)
                    var stale = existing.snapshot
                    stale.status = .cached
                    cache[accountID] = existing
                    results[accountID] = stale
                } else {
                    if is429 {
                        let hits = (cache[accountID]?.rateLimitHits ?? 0) + 1
                        let backoffSeconds = min(3600.0, 60.0 * pow(2.0, Double(hits - 1)))
                        cache[accountID] = CacheRecord(
                            snapshot: snapshot,
                            rateLimitHits: hits,
                            cooldownUntil: now.addingTimeInterval(backoffSeconds)
                        )
                    }
                    results[accountID] = snapshot
                }
            case .cached, .notConfigured:
                results[accountID] = snapshot
            }
        }

        return results
    }
}
