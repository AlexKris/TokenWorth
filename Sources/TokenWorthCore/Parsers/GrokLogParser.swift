import Foundation

public struct GrokLogParser: UsageLogParser {
    public let provider: ProviderID = .grok

    public init() {}

    public func discoverFiles(for account: AccountProfile) -> [URL] {
        let root: URL
        if let custom = account.customLogDirectory?.trimmingCharacters(in: .whitespacesAndNewlines), !custom.isEmpty {
            root = URL(fileURLWithPath: AppPaths.expandTilde(custom), isDirectory: true)
        } else {
            root = AppPaths.homeDirectory.appendingPathComponent(".grok", isDirectory: true)
        }

        var files: [URL] = []
        let unified = root.appendingPathComponent("logs/unified.jsonl")
        if FileManager.default.fileExists(atPath: unified.path) {
            files.append(unified)
        }

        let sessionsDir = root.appendingPathComponent("sessions", isDirectory: true)
        let sessionEvents = LogParserHelpers.discoverFiles(under: sessionsDir) { url in
            url.lastPathComponent == "events.jsonl"
        }
        files.append(contentsOf: sessionEvents)

        // If a custom directory points directly to jsonl logs (not standard ~/.grok hierarchy), pick them up too.
        if files.isEmpty {
            files = LogParserHelpers.discoverFiles(under: root) { url in
                url.pathExtension.lowercased() == "jsonl"
            }
        }

        return Array(Set(files)).sorted { $0.path < $1.path }
    }

    public func parseFile(at url: URL, accountID: String) throws -> [UsageEvent] {
        var events: [UsageEvent] = []
        var currentModel = readSessionSummaryModel(near: url) ?? "grok-build-0.1"
        let defaultSessionID = inferSessionID(from: url)
        let fallbackDate = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date()

        try LogParserHelpers.streamJSONObjects(at: url) { _, obj in
            // Track active model updates from turn_started events in events.jsonl.
            if let turnStarted = obj["turn_started"] as? [String: Any],
               let model = LogParserHelpers.stringValue(turnStarted["model_id"]) {
                currentModel = model
            }
            if let eventName = LogParserHelpers.stringValue(obj["event"]) ?? LogParserHelpers.stringValue(obj["type"]),
               eventName == "turn_started" {
                let payload = obj["payload"] as? [String: Any]
                if let model = LogParserHelpers.stringValue(obj["model_id"])
                    ?? LogParserHelpers.stringValue(payload?["model_id"])
                    ?? LogParserHelpers.stringValue(payload?["model"]) {
                    currentModel = model
                }
            }

            let eventType = LogParserHelpers.stringValue(obj["event"]) ?? LogParserHelpers.stringValue(obj["type"]) ?? ""
            let ctx = (obj["ctx"] as? [String: Any])
                ?? (obj["usage"] as? [String: Any])
                ?? ((obj["payload"] as? [String: Any])?["usage"] as? [String: Any])
                ?? (obj["payload"] as? [String: Any])
                ?? obj

            let hasUsageFields =
                ctx["prompt_tokens"] != nil ||
                ctx["completion_tokens"] != nil ||
                ctx["input_tokens"] != nil ||
                ctx["output_tokens"] != nil

            let isInferenceDone = eventType == "shell.turn.inference_done" || eventType == "inference_done" || hasUsageFields
            guard isInferenceDone, hasUsageFields else { return }

            let promptTokens = LogParserHelpers.intValue(ctx["prompt_tokens"])
                ?? LogParserHelpers.intValue(ctx["input_tokens"])
                ?? 0
            let cachedTokens = LogParserHelpers.intValue(ctx["cached_prompt_tokens"])
                ?? LogParserHelpers.intValue(ctx["cached_input_tokens"])
                ?? LogParserHelpers.intValue(ctx["cache_read_input_tokens"])
                ?? 0
            let completionTokens = LogParserHelpers.intValue(ctx["completion_tokens"])
                ?? LogParserHelpers.intValue(ctx["output_tokens"])
                ?? 0
            let reasoningTokens = LogParserHelpers.intValue(ctx["reasoning_tokens"])
                ?? LogParserHelpers.intValue(ctx["reasoning_output_tokens"])
                ?? 0

            let uncachedInput = max(0, promptTokens - cachedTokens)
            let tokens = TokenCounts(
                input: uncachedInput,
                output: completionTokens,
                cacheRead: cachedTokens,
                cacheWrite: 0,
                reasoning: reasoningTokens
            )
            guard tokens.total > 0 else { return }

            let model = LogParserHelpers.stringValue(ctx["model_id"])
                ?? LogParserHelpers.stringValue(ctx["model"])
                ?? LogParserHelpers.stringValue(obj["model_id"])
                ?? LogParserHelpers.stringValue(obj["model"])
                ?? currentModel

            let sid = LogParserHelpers.stringValue(obj["sid"])
                ?? LogParserHelpers.stringValue(obj["session_id"])
                ?? LogParserHelpers.stringValue(ctx["sid"])
                ?? defaultSessionID

            let timestamp = LogParserHelpers.parseDate(obj["ts"])
                ?? LogParserHelpers.parseDate(obj["timestamp"])
                ?? fallbackDate

            let secondBucket = Int(timestamp.timeIntervalSince1970)
            let fingerprint = "grok:\(sid):\(secondBucket):\(promptTokens):\(cachedTokens):\(completionTokens)"

            events.append(
                UsageEvent(
                    id: fingerprint,
                    provider: .grok,
                    accountID: accountID,
                    model: model,
                    timestamp: timestamp,
                    tokens: tokens,
                    sessionID: sid,
                    sourceFile: url.path
                )
            )
        }

        return events
    }

    private func readSessionSummaryModel(near eventsURL: URL) -> String? {
        guard eventsURL.lastPathComponent == "events.jsonl" else { return nil }
        let summaryURL = eventsURL.deletingLastPathComponent().appendingPathComponent("summary.json")
        guard let data = try? Data(contentsOf: summaryURL),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return LogParserHelpers.stringValue(obj["current_model_id"])
            ?? LogParserHelpers.stringValue(obj["model_id"])
            ?? LogParserHelpers.stringValue(obj["model"])
    }

    private func inferSessionID(from url: URL) -> String {
        if url.lastPathComponent == "events.jsonl" {
            return url.deletingLastPathComponent().lastPathComponent
        }
        return url.deletingPathExtension().lastPathComponent
    }
}
