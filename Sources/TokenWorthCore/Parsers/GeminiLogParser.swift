import Foundation

public struct GeminiLogParser: UsageLogParser {
    public let provider: ProviderID = .antigravity

    public init() {}

    public func discoverFiles(for account: AccountProfile) -> [URL] {
        var files: [URL] = []

        if let custom = account.customLogDirectory?.trimmingCharacters(in: .whitespacesAndNewlines), !custom.isEmpty {
            let customURL = URL(fileURLWithPath: AppPaths.expandTilde(custom), isDirectory: true)
            files.append(contentsOf: LogParserHelpers.discoverFiles(under: customURL) { url in
                Self.isSupportedFile(url)
            })
        } else {
            let geminiTmp = AppPaths.homeDirectory.appendingPathComponent(".gemini/tmp", isDirectory: true)
            files.append(contentsOf: LogParserHelpers.discoverFiles(under: geminiTmp) { url in
                let name = url.lastPathComponent
                return name.hasPrefix("session-") && url.pathExtension.lowercased() == "json"
            })

            files.append(contentsOf: LogParserHelpers.discoverFiles(under: AppPaths.importsDirectory) { url in
                Self.isSupportedFile(url)
            })
        }

        return Array(Set(files)).sorted { $0.path < $1.path }
    }

    private static func isSupportedFile(_ url: URL) -> Bool {
        let name = url.lastPathComponent
        let ext = url.pathExtension.lowercased()
        if ext == "jsonl" { return true }
        return ext == "json" && name.hasPrefix("session-")
    }

    public func parseFile(at url: URL, accountID: String) throws -> [UsageEvent] {
        if url.pathExtension.lowercased() == "jsonl" {
            return try parseImportedJSONL(at: url, accountID: accountID)
        }
        return try parseGeminiSessionJSON(at: url, accountID: accountID)
    }

    private func parseGeminiSessionJSON(at url: URL, accountID: String) throws -> [UsageEvent] {
        let data = try Data(contentsOf: url)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let messages = root["messages"] as? [[String: Any]] else {
            return []
        }

        let sessionID = LogParserHelpers.stringValue(root["sessionId"])
            ?? url.deletingPathExtension().lastPathComponent
        let defaultModel = LogParserHelpers.stringValue(root["model"]) ?? "gemini-2.5-pro"
        let sessionStart = LogParserHelpers.parseDate(root["startTime"])
            ?? (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            ?? Date()

        var events: [UsageEvent] = []
        for (idx, msg) in messages.enumerated() {
            guard let tokensObj = msg["tokens"] as? [String: Any] else { continue }

            let input = LogParserHelpers.intValue(tokensObj["input"]) ?? 0
            let cached = LogParserHelpers.intValue(tokensObj["cached"]) ?? 0
            let output = LogParserHelpers.intValue(tokensObj["output"]) ?? 0
            let thoughts = LogParserHelpers.intValue(tokensObj["thoughts"]) ?? 0

            let uncachedInput = max(0, input - cached)
            let billableOutput = output + thoughts

            let tokens = TokenCounts(
                input: uncachedInput,
                output: billableOutput,
                cacheRead: cached,
                cacheWrite: 0,
                reasoning: thoughts
            )
            guard tokens.total > 0 else { continue }

            let model = LogParserHelpers.stringValue(msg["model"]) ?? defaultModel
            let timestamp = LogParserHelpers.parseDate(msg["timestamp"]) ?? sessionStart
            let messageID = LogParserHelpers.stringValue(msg["id"]) ?? String(idx)

            events.append(
                UsageEvent(
                    id: "gemini:\(sessionID):\(messageID)",
                    provider: .antigravity,
                    accountID: accountID,
                    model: model,
                    timestamp: timestamp,
                    tokens: tokens,
                    sessionID: sessionID,
                    sourceFile: url.path
                )
            )
        }

        return events
    }

    private func parseImportedJSONL(at url: URL, accountID: String) throws -> [UsageEvent] {
        var events: [UsageEvent] = []
        let fallbackDate = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date()

        try LogParserHelpers.streamJSONObjects(at: url) { lineIndex, obj in
            let rawProvider = LogParserHelpers.stringValue(obj["provider"])?.lowercased()
            let eventProvider: ProviderID
            if let rawProvider, let matched = ProviderID(rawValue: rawProvider) {
                eventProvider = matched
            } else if rawProvider == "gemini" {
                eventProvider = .antigravity
            } else {
                eventProvider = .antigravity
            }

            let model = LogParserHelpers.stringValue(obj["model"]) ?? "gemini-4-neon"
            let input = LogParserHelpers.intValue(obj["input_tokens"]) ?? 0
            let cached = LogParserHelpers.intValue(obj["cache_read_tokens"])
                ?? LogParserHelpers.intValue(obj["cached_tokens"])
                ?? 0
            let cacheWrite = LogParserHelpers.intValue(obj["cache_write_tokens"]) ?? 0
            let output = LogParserHelpers.intValue(obj["output_tokens"]) ?? 0
            let reasoning = LogParserHelpers.intValue(obj["reasoning_tokens"]) ?? 0

            let tokens = TokenCounts(
                input: input,
                output: output,
                cacheRead: cached,
                cacheWrite: cacheWrite,
                reasoning: reasoning
            )
            guard tokens.total > 0 else { return }

            let timestamp = LogParserHelpers.parseDate(obj["timestamp"]) ?? fallbackDate
            let lineID = LogParserHelpers.stringValue(obj["id"]) ?? "\(url.lastPathComponent):\(lineIndex)"
            let sessionID = LogParserHelpers.stringValue(obj["session_id"])

            events.append(
                UsageEvent(
                    id: "import:\(lineID)",
                    provider: eventProvider,
                    accountID: accountID,
                    model: model,
                    timestamp: timestamp,
                    tokens: tokens,
                    sessionID: sessionID,
                    sourceFile: url.path
                )
            )
        }
        return events
    }
}
