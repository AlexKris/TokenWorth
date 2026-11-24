import Foundation

public struct ClaudeLogParser: UsageLogParser {
    public let provider: ProviderID = .claude

    public init() {}

    public func discoverFiles(for account: AccountProfile) -> [URL] {
        let root: URL
        if let custom = account.customLogDirectory?.trimmingCharacters(in: .whitespacesAndNewlines), !custom.isEmpty {
            let customURL = URL(fileURLWithPath: AppPaths.expandTilde(custom), isDirectory: true)
            let projectsSubdir = customURL.appendingPathComponent("projects", isDirectory: true)
            root = FileManager.default.fileExists(atPath: projectsSubdir.path) ? projectsSubdir : customURL
        } else {
            root = AppPaths.homeDirectory.appendingPathComponent(".claude/projects", isDirectory: true)
        }

        return LogParserHelpers.discoverFiles(under: root) { url in
            url.pathExtension.lowercased() == "jsonl"
        }
    }

    public func parseFile(at url: URL, accountID: String) throws -> [UsageEvent] {
        struct Candidate {
            let lineIndex: Int
            let event: UsageEvent
        }

        var deduplicated: [String: Candidate] = [:]
        let fileModificationDate = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date()

        try LogParserHelpers.streamJSONObjects(at: url) { lineIndex, obj in
            guard let type = LogParserHelpers.stringValue(obj["type"]), type == "assistant" else {
                return
            }
            guard let message = obj["message"] as? [String: Any],
                  let usage = message["usage"] as? [String: Any] else {
                return
            }

            let model = LogParserHelpers.stringValue(message["model"]) ?? "claude-sonnet-4-5"
            if model == "<synthetic>" {
                return
            }

            let inputTokens = LogParserHelpers.intValue(usage["input_tokens"]) ?? 0
            let cacheWriteTokens = LogParserHelpers.intValue(usage["cache_creation_input_tokens"]) ?? 0
            let cacheReadTokens = LogParserHelpers.intValue(usage["cache_read_input_tokens"]) ?? 0
            let outputTokens = LogParserHelpers.intValue(usage["output_tokens"]) ?? 0

            let details = usage["output_tokens_details"] as? [String: Any]
            let thinkingTokens = LogParserHelpers.intValue(details?["thinking_tokens"])
                ?? LogParserHelpers.intValue(usage["thinking_tokens"])
                ?? 0

            let tokens = TokenCounts(
                input: inputTokens,
                output: outputTokens,
                cacheRead: cacheReadTokens,
                cacheWrite: cacheWriteTokens,
                reasoning: thinkingTokens
            )
            guard tokens.total > 0 else { return }

            let requestID = LogParserHelpers.stringValue(obj["requestId"])
            let messageID = LogParserHelpers.stringValue(message["id"])
            let uuid = LogParserHelpers.stringValue(obj["uuid"])
            let sessionID = LogParserHelpers.stringValue(obj["sessionId"])
            let timestamp = LogParserHelpers.parseDate(obj["timestamp"]) ?? fileModificationDate

            let dedupKey: String
            if let messageID, let requestID {
                dedupKey = "\(messageID):\(requestID)"
            } else if let requestID {
                dedupKey = "req:\(requestID)"
            } else if let messageID {
                dedupKey = "msg:\(messageID)"
            } else if let uuid {
                dedupKey = "uuid:\(uuid)"
            } else {
                dedupKey = "\(url.path):\(lineIndex)"
            }

            let event = UsageEvent(
                id: "claude:\(dedupKey)",
                provider: .claude,
                accountID: accountID,
                model: model,
                timestamp: timestamp,
                tokens: tokens,
                sessionID: sessionID,
                sourceFile: url.path
            )

            // Last-Write-Wins preferring finalized streaming chunk (max output_tokens / total tokens, then latest line).
            if let existing = deduplicated[dedupKey] {
                let candidateIsNewer =
                    event.tokens.output > existing.event.tokens.output ||
                    (event.tokens.output == existing.event.tokens.output && event.tokens.total > existing.event.tokens.total) ||
                    (event.tokens.total == existing.event.tokens.total && lineIndex > existing.lineIndex)
                if candidateIsNewer {
                    deduplicated[dedupKey] = Candidate(lineIndex: lineIndex, event: event)
                }
            } else {
                deduplicated[dedupKey] = Candidate(lineIndex: lineIndex, event: event)
            }
        }

        return deduplicated.values
            .sorted { $0.lineIndex < $1.lineIndex }
            .map(\.event)
    }
}
