import Foundation

public struct CodexLogParser: UsageLogParser {
    public let provider: ProviderID = .codex

    public init() {}

    public func discoverFiles(for account: AccountProfile) -> [URL] {
        let root: URL
        if let custom = account.customLogDirectory?.trimmingCharacters(in: .whitespacesAndNewlines), !custom.isEmpty {
            let customURL = URL(fileURLWithPath: AppPaths.expandTilde(custom), isDirectory: true)
            let sessionsSubdir = customURL.appendingPathComponent("sessions", isDirectory: true)
            root = FileManager.default.fileExists(atPath: sessionsSubdir.path) ? sessionsSubdir : customURL
        } else {
            root = AppPaths.homeDirectory.appendingPathComponent(".codex/sessions", isDirectory: true)
        }

        return LogParserHelpers.discoverFiles(under: root) { url in
            url.pathExtension.lowercased() == "jsonl"
        }
    }

    private struct RawCodexUsage: Equatable {
        let inputTokens: Int
        let cachedInputTokens: Int
        let outputTokens: Int
        let reasoningOutputTokens: Int

        init?(dict: [String: Any]?) {
            guard let dict else { return nil }
            let input = LogParserHelpers.intValue(dict["input_tokens"]) ?? 0
            let cached = LogParserHelpers.intValue(dict["cached_input_tokens"]) ?? 0
            let output = LogParserHelpers.intValue(dict["output_tokens"]) ?? 0
            let reasoning = LogParserHelpers.intValue(dict["reasoning_output_tokens"]) ?? 0
            self.inputTokens = input
            self.cachedInputTokens = cached
            self.outputTokens = output
            self.reasoningOutputTokens = reasoning
        }

        var isZero: Bool {
            inputTokens == 0 && cachedInputTokens == 0 && outputTokens == 0 && reasoningOutputTokens == 0
        }
    }

    public func parseFile(at url: URL, accountID: String) throws -> [UsageEvent] {
        var events: [UsageEvent] = []
        var currentModel = "gpt-5-codex"
        var sessionID: String? = url.deletingPathExtension().lastPathComponent
        var previousTotal: RawCodexUsage?
        let fallbackDate = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date()

        try LogParserHelpers.streamJSONObjects(at: url) { lineIndex, obj in
            guard let type = LogParserHelpers.stringValue(obj["type"]) else { return }
            let payload = obj["payload"] as? [String: Any]

            if type == "session_meta" {
                if let sid = LogParserHelpers.stringValue(payload?["id"]) {
                    sessionID = sid
                }
                if let model = LogParserHelpers.stringValue(payload?["model"]) {
                    currentModel = model
                }
                return
            }

            if type == "turn_context" {
                if let model = LogParserHelpers.stringValue(payload?["model"])
                    ?? LogParserHelpers.stringValue(payload?["model_name"]) {
                    currentModel = model
                }
                return
            }

            guard type == "event_msg",
                  let payload,
                  LogParserHelpers.stringValue(payload["type"]) == "token_count",
                  let info = payload["info"] as? [String: Any] else {
                return
            }

            if let model = LogParserHelpers.stringValue(info["model"]) ?? LogParserHelpers.stringValue(payload["model"]) {
                currentModel = model
            }

            let totalUsage = RawCodexUsage(dict: info["total_token_usage"] as? [String: Any])
            let lastUsage = RawCodexUsage(dict: info["last_token_usage"] as? [String: Any])

            // Skip repeated identical cumulative snapshots to avoid double-counting.
            if let totalUsage, let previousTotal, totalUsage == previousTotal {
                return
            }

            let delta: RawCodexUsage?
            if let lastUsage, !lastUsage.isZero {
                delta = lastUsage
            } else if let totalUsage {
                let prev = previousTotal ?? RawCodexUsage(dict: [:])!
                let diff = RawCodexUsage(dict: [
                    "input_tokens": max(0, totalUsage.inputTokens - prev.inputTokens),
                    "cached_input_tokens": max(0, totalUsage.cachedInputTokens - prev.cachedInputTokens),
                    "output_tokens": max(0, totalUsage.outputTokens - prev.outputTokens),
                    "reasoning_output_tokens": max(0, totalUsage.reasoningOutputTokens - prev.reasoningOutputTokens)
                ])
                delta = diff
            } else {
                delta = nil
            }

            if let totalUsage {
                previousTotal = totalUsage
            }

            guard let delta, !delta.isZero else { return }

            // Codex `input_tokens` includes `cached_input_tokens`; `output_tokens` includes `reasoning_output_tokens`.
            let uncachedInput = max(0, delta.inputTokens - delta.cachedInputTokens)
            let tokens = TokenCounts(
                input: uncachedInput,
                output: delta.outputTokens,
                cacheRead: delta.cachedInputTokens,
                cacheWrite: 0,
                reasoning: delta.reasoningOutputTokens
            )
            guard tokens.total > 0 else { return }

            let timestamp = LogParserHelpers.parseDate(obj["timestamp"]) ?? fallbackDate
            let event = UsageEvent(
                id: "codex:\(sessionID ?? url.lastPathComponent):\(lineIndex)",
                provider: .codex,
                accountID: accountID,
                model: currentModel,
                timestamp: timestamp,
                tokens: tokens,
                sessionID: sessionID,
                sourceFile: url.path
            )
            events.append(event)
        }

        return events
    }
}
