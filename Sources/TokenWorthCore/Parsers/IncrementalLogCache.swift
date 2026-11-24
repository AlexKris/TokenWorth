import Foundation

public actor IncrementalLogCache {
    private struct FileFingerprint: Equatable {
        let size: UInt64
        let modifiedTime: TimeInterval
    }

    private struct CachedEntry {
        let fingerprint: FileFingerprint
        let events: [UsageEvent]
    }

    private var entries: [String: CachedEntry] = [:]
    private let parsersByProvider: [ProviderID: any UsageLogParser]

    public init(parsers: [any UsageLogParser] = IncrementalLogCache.defaultParsers()) {
        var map: [ProviderID: any UsageLogParser] = [:]
        for parser in parsers {
            map[parser.provider] = parser
        }
        self.parsersByProvider = map
    }

    public static func defaultParsers() -> [any UsageLogParser] {
        [
            ClaudeLogParser(),
            CodexLogParser(),
            GrokLogParser(),
            GeminiLogParser()
        ]
    }

    public func clear() {
        entries.removeAll()
    }

    public func scanAll(accounts: [AccountProfile]) -> [UsageEvent] {
        var activeCacheKeys = Set<String>()
        var defaultDirClaimedForProvider = Set<ProviderID>()
        var eventsByProviderAndID: [String: UsageEvent] = [:]

        // Prefer active accounts first when claiming the default shared log directory for a provider.
        let orderedAccounts = accounts.sorted { lhs, rhs in
            if lhs.isActive != rhs.isActive { return lhs.isActive && !rhs.isActive }
            return lhs.id < rhs.id
        }

        for account in orderedAccounts {
            guard let parser = parsersByProvider[account.provider] else { continue }

            let usesCustomDir = !(account.customLogDirectory?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
            if !usesCustomDir {
                if defaultDirClaimedForProvider.contains(account.provider) {
                    continue
                }
                defaultDirClaimedForProvider.insert(account.provider)
            }

            let files = parser.discoverFiles(for: account)
            for fileURL in files {
                let cacheKey = "\(account.id)::\(fileURL.path)"
                activeCacheKeys.insert(cacheKey)

                let events = cachedOrParse(fileURL: fileURL, cacheKey: cacheKey, accountID: account.id, parser: parser)
                for event in events {
                    let dedupKey = "\(event.provider.rawValue)::\(event.id)"
                    if let existing = eventsByProviderAndID[dedupKey] {
                        if event.tokens.total > existing.tokens.total ||
                            (event.tokens.total == existing.tokens.total && event.timestamp > existing.timestamp) {
                            eventsByProviderAndID[dedupKey] = event
                        }
                    } else {
                        eventsByProviderAndID[dedupKey] = event
                    }
                }
            }
        }

        // Evict entries for files that were removed or belong to removed accounts.
        for key in entries.keys where !activeCacheKeys.contains(key) {
            entries.removeValue(forKey: key)
        }

        return eventsByProviderAndID.values.sorted { $0.timestamp < $1.timestamp }
    }

    private func cachedOrParse(
        fileURL: URL,
        cacheKey: String,
        accountID: String,
        parser: any UsageLogParser
    ) -> [UsageEvent] {
        guard let fingerprint = Self.fingerprint(for: fileURL) else {
            return []
        }
        if let cached = entries[cacheKey], cached.fingerprint == fingerprint {
            return cached.events
        }
        do {
            let parsed = try parser.parseFile(at: fileURL, accountID: accountID)
            entries[cacheKey] = CachedEntry(fingerprint: fingerprint, events: parsed)
            return parsed
        } catch {
            return []
        }
    }

    private static func fingerprint(for url: URL) -> FileFingerprint? {
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]) else {
            return nil
        }
        let size = UInt64(max(0, values.fileSize ?? 0))
        let mod = values.contentModificationDate?.timeIntervalSince1970 ?? 0
        return FileFingerprint(size: size, modifiedTime: mod)
    }
}
