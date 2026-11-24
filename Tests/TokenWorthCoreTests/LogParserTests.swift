import Foundation
import Testing
@testable import TokenWorthCore

@Suite("Incremental Log Parsers")
struct LogParserTests {
    private func makeTempDir() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("TokenWorthTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test("ClaudeLogParser deduplicates streaming chunks using Last-Write-Wins")
    func claudeStreamingDedup() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let fileURL = dir.appendingPathComponent("session.jsonl")
        let content = """
        {"type":"user","timestamp":"2026-11-24T08:00:00Z","message":{"role":"user","content":"hi"}}
        {"type":"assistant","requestId":"req_1","timestamp":"2026-11-24T08:00:01Z","sessionId":"s1","message":{"id":"msg_1","model":"claude-sonnet-4-6","usage":{"input_tokens":10,"cache_creation_input_tokens":2000,"cache_read_input_tokens":5000,"output_tokens":12}}}
        {"type":"assistant","requestId":"req_1","timestamp":"2026-11-24T08:00:03Z","sessionId":"s1","message":{"id":"msg_1","model":"claude-sonnet-4-6","usage":{"input_tokens":10,"cache_creation_input_tokens":2000,"cache_read_input_tokens":5000,"output_tokens":180,"output_tokens_details":{"thinking_tokens":40}}}}
        {"type":"assistant","requestId":"req_2","timestamp":"2026-11-24T08:01:00Z","sessionId":"s1","message":{"id":"msg_2","model":"<synthetic>","usage":{"input_tokens":0,"output_tokens":5}}}
        """
        try content.write(to: fileURL, atomically: true, encoding: .utf8)

        let parser = ClaudeLogParser()
        let events = try parser.parseFile(at: fileURL, accountID: "claude-1")

        #expect(events.count == 1)
        #expect(events[0].model == "claude-sonnet-4-6")
        #expect(events[0].tokens.input == 10)
        #expect(events[0].tokens.cacheWrite == 2000)
        #expect(events[0].tokens.cacheRead == 5000)
        #expect(events[0].tokens.output == 180)
        #expect(events[0].tokens.reasoning == 40)
    }

    @Test("CodexLogParser skips duplicate cumulative snapshots and subtracts cached input")
    func codexCumulativeAndCachedSubtraction() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let fileURL = dir.appendingPathComponent("codex-session.jsonl")
        let content = """
        {"timestamp":"2026-11-24T09:00:00Z","type":"session_meta","payload":{"id":"codex-s1","model":"gpt-5.2-codex"}}
        {"timestamp":"2026-11-24T09:00:01Z","type":"event_msg","payload":{"type":"token_count","info":null}}
        {"timestamp":"2026-11-24T09:00:05Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":15000,"cached_input_tokens":10000,"output_tokens":500,"reasoning_output_tokens":120},"last_token_usage":{"input_tokens":15000,"cached_input_tokens":10000,"output_tokens":500,"reasoning_output_tokens":120}}}}
        {"timestamp":"2026-11-24T09:00:06Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":15000,"cached_input_tokens":10000,"output_tokens":500,"reasoning_output_tokens":120},"last_token_usage":{"input_tokens":15000,"cached_input_tokens":10000,"output_tokens":500,"reasoning_output_tokens":120}}}}
        {"timestamp":"2026-11-24T09:00:10Z","type":"turn_context","payload":{"model":"gpt-5.3-codex"}}
        {"timestamp":"2026-11-24T09:00:15Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":20000,"cached_input_tokens":14000,"output_tokens":800,"reasoning_output_tokens":220},"last_token_usage":{"input_tokens":5000,"cached_input_tokens":4000,"output_tokens":300,"reasoning_output_tokens":100}}}}
        """
        try content.write(to: fileURL, atomically: true, encoding: .utf8)

        let parser = CodexLogParser()
        let events = try parser.parseFile(at: fileURL, accountID: "codex-1")

        #expect(events.count == 2)
        #expect(events[0].model == "gpt-5.2-codex")
        #expect(events[0].tokens.input == 5000)
        #expect(events[0].tokens.cacheRead == 10000)
        #expect(events[0].tokens.output == 500)
        #expect(events[0].tokens.reasoning == 120)

        #expect(events[1].model == "gpt-5.3-codex")
        #expect(events[1].tokens.input == 1000)
        #expect(events[1].tokens.cacheRead == 4000)
        #expect(events[1].tokens.output == 300)
        #expect(events[1].tokens.reasoning == 100)
    }

    @Test("GrokLogParser + IncrementalLogCache deduplicate unified.jsonl and session events.jsonl")
    func grokCrossFileDedupAndCaching() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let logsDir = dir.appendingPathComponent("logs", isDirectory: true)
        let sessionDir = dir.appendingPathComponent("sessions/proj/sid-42", isDirectory: true)
        try FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: sessionDir, withIntermediateDirectories: true)

        try #"{"current_model_id":"grok-4.7"}"#.write(
            to: sessionDir.appendingPathComponent("summary.json"),
            atomically: true,
            encoding: .utf8
        )

        let unifiedLine = #"{"ts":"2026-11-24T10:00:00Z","sid":"sid-42","event":"shell.turn.inference_done","model_id":"grok-4.7","ctx":{"prompt_tokens":12000,"cached_prompt_tokens":8000,"completion_tokens":450,"reasoning_tokens":90}}"#
        try (unifiedLine + "\n").write(
            to: logsDir.appendingPathComponent("unified.jsonl"),
            atomically: true,
            encoding: .utf8
        )

        let sessionEvents = """
        {"ts":"2026-11-24T09:59:58Z","event":"turn_started","turn_started":{"model_id":"grok-4.7"}}
        {"ts":"2026-11-24T10:00:00Z","sid":"sid-42","event":"shell.turn.inference_done","ctx":{"prompt_tokens":12000,"cached_prompt_tokens":8000,"completion_tokens":450,"reasoning_tokens":90}}
        {"ts":"2026-11-24T10:05:00Z","sid":"sid-42","event":"shell.turn.inference_done","ctx":{"prompt_tokens":3000,"cached_prompt_tokens":1000,"completion_tokens":200,"reasoning_tokens":0}}
        """
        try sessionEvents.write(
            to: sessionDir.appendingPathComponent("events.jsonl"),
            atomically: true,
            encoding: .utf8
        )

        let account = AccountProfile(
            id: "grok-test",
            provider: .grok,
            displayName: "Grok Test",
            planName: "SuperGrok",
            customLogDirectory: dir.path
        )

        let cache = IncrementalLogCache()
        let events = await cache.scanAll(accounts: [account])
        #expect(events.count == 2)
        #expect(events[0].tokens.input == 4000)
        #expect(events[0].tokens.cacheRead == 8000)
        #expect(events[0].tokens.output == 450)
        #expect(events[1].tokens.input == 2000)

        // Second scan uses cache and still yields identical 2 events.
        let secondScan = await cache.scanAll(accounts: [account])
        #expect(secondScan == events)
    }

    @Test("GeminiLogParser parses session JSON with cached subtraction and thoughts added to billable output")
    func geminiSessionParsing() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let sessionURL = dir.appendingPathComponent("session-2026-11-24.json")
        let payload = """
        {
          "sessionId": "gem-s1",
          "startTime": "2026-11-24T08:00:00Z",
          "messages": [
            {"id": "m1", "type": "user", "content": "hello"},
            {
              "id": "m2",
              "type": "gemini",
              "model": "gemini-4-neon",
              "timestamp": "2026-11-24T08:00:05Z",
              "tokens": {"input": 10000, "cached": 6000, "output": 300, "thoughts": 150}
            }
          ]
        }
        """
        try payload.write(to: sessionURL, atomically: true, encoding: .utf8)

        let parser = GeminiLogParser()
        let events = try parser.parseFile(at: sessionURL, accountID: "ag-1")

        #expect(events.count == 1)
        #expect(events[0].model == "gemini-4-neon")
        #expect(events[0].tokens.input == 4000)
        #expect(events[0].tokens.cacheRead == 6000)
        #expect(events[0].tokens.output == 450)
        #expect(events[0].tokens.reasoning == 150)
    }
}
