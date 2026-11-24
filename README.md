# TokenWorth

**Native macOS menu bar app & CLI for tracking AI subscription quotas, local token consumption, and API-equivalent value.**

> *"See both how much quota you have left — and what your AI tokens are actually worth."*

TokenWorth combines the quick-glance menu bar quota monitor experience (inspired by [OpenUsage](https://github.com/robinebers/openusage)) with local, privacy-first token accounting and API-equivalent pricing across **Claude**, **Codex (OpenAI)**, **Grok**, and **Antigravity / Gemini**.

---

## Features

- **Account Quota Windows & Burn Pace**
  - Tracks `5h` rolling session windows, `7d` weekly limits, model-specific caps, and extra-usage credits.
  - Renders a linear **burn pace marker (`▼`)** on each quota bar so you can immediately tell if your consumption is ahead of or behind schedule, plus exact reset countdowns.
  - Supports multi-account cards per provider with optional email masking (`t•••••@g••••••`) and Phase-2-ready account metadata.
- **Local Token Accounting & API-Equivalent Valuation**
  - Incrementally parses local CLI logs (`IncrementalLogCache` keyed by file size & mtime) with deduplication against streaming/cumulative double-counting.
  - Breaks down **Uncached Input**, **Output**, **Prompt Cache Read**, **Prompt Cache Write**, and **Reasoning / Thinking** tokens.
  - Calculates **API-equivalent dollar cost** (USD & configurable CNY conversion), **prompt-cache dollar savings**, daily stacked cost charts (`Charts`), per-model breakdowns, and **Subscription ROI** (`API Value / Monthly Subscription`).
- **Privacy-First & Read-Only**
  - Zero telemetry; never sends conversation content or logs off your machine.
  - Strictly read-only toward `~/.claude`, `~/.codex`, `~/.grok`, and `~/.gemini`.
  - macOS Keychain reads are **off by default** (explicit opt-in in Settings) to avoid unexpected OS prompts.
- **Companion CLI (`tokenworth`)**
  - Query `summary`, `models`, `daily`, `quota`, and `pricing` in terminal tables or `--json`.

---

## Supported Providers & Data Sources

| Provider | Quota Source (Read-Only) | Token Log Source | Deduplication & Billing Rules |
| --- | --- | --- | --- |
| **Claude** | `~/.claude/.credentials.json` (or optional opt-in Keychain `"Claude Code-credentials"`) → `api.anthropic.com/api/oauth/usage` | `~/.claude/projects/**/*.jsonl` | Last-Write-Wins on `message.id + requestId`; tracks `cache_creation_input_tokens` and `cache_read_input_tokens` |
| **Codex** | `~/.codex/auth.json` → `chatgpt.com/backend-api/wham/usage` | `~/.codex/sessions/**/*.jsonl` | Skips duplicate cumulative `total_token_usage` snapshots; subtracts `cached_input_tokens` from `input_tokens`; prevents double-billing `reasoning_output_tokens` |
| **Grok** | `~/.grok/auth.json` → `cli-chat-proxy.grok.com/v1/billing` (or external JSON/command) | `~/.grok/logs/unified.jsonl` & `~/.grok/sessions/*/*/events.jsonl` | Deduplicates overlapping turns between `unified.jsonl` and session `events.jsonl` |
| **Antigravity / Gemini** | Sanctioned local JSON (`~/Library/Application Support/TokenWorth/antigravity-quota.json`) or user-configured CLI bridge | `~/.gemini/tmp/*/chats/session-*.json` & `~/Library/Application Support/TokenWorth/imports/*.jsonl` | Subtracts `cached` from `input`; adds `thoughts` into billable output while displaying reasoning separately |

---

## Build & Run

Works on macOS 14+ with **Apple Swift 6.0+ (Command Line Tools alone — no full Xcode required)**.

```bash
git clone https://github.com/AlexKris/TokenWorth.git
cd TokenWorth

# Run unit tests (if using Xcode or GitHub Actions CI)
swift test

# If using Apple Command Line Tools alone (without Xcode.app)
swift test -Xswiftc -plugin-path -Xswiftc /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing

# Build & launch the menu bar app bundle
./scripts/build-app.sh
open dist/TokenWorth.app
```

Want to preview all charts and multi-account cards immediately without local logs? Open **Settings (`⚙`) → Demo Mode**, or pass `--demo` to the CLI.

---

## Companion CLI (`tokenworth`)

After running `./scripts/build-app.sh`, the standalone CLI binary is at `dist/tokenworth` (or invoke directly via `swift run tokenworth-cli`):

```bash
# Aggregate summary (Today / 7D / 30D / All)
./dist/tokenworth summary --range 7d
./dist/tokenworth summary --demo --cny

# Per-model token & cost breakdown
./dist/tokenworth models --demo --provider claude

# Daily stacked usage series
./dist/tokenworth daily --demo --json

# Check live or demo quota windows
./dist/tokenworth quota --demo

# Inspect built-in & overridden API pricing
./dist/tokenworth pricing --query gemini
```

---

## Configuration & Bridges

TokenWorth stores only its own config and bridges under `~/Library/Application Support/TokenWorth/`:

- `settings.json` — accounts, currency (`USD` / `CNY`), refresh cadence, menu bar badge mode (`Highest Quota`, `Today Cost`, `Icon Only`), email masking, and opt-in Keychain toggle.
- `pricing-overrides.json` — optional custom pricing array (`[ModelPricing]`) or LiteLLM-format JSON dictionary overriding built-in rates.
- `antigravity-quota.json` — optional quota feed for Antigravity / Gemini accounts (can be generated as a template from **Settings → Create Quota JSON Template**):

```json
{
  "accounts": [
    {
      "accountID": "antigravity-default",
      "planName": "Google AI Ultra",
      "groups": [
        {
          "title": "Gemini Models",
          "windows": [
            { "label": "7d", "durationSeconds": 604800, "usedPercent": 1, "resetsAt": "2026-12-01T09:00:00+08:00" },
            { "label": "5h", "durationSeconds": 18000, "usedPercent": 2, "resetsAt": "2026-11-24T14:00:00+08:00" }
          ]
        }
      ]
    }
  ]
}
```

- `imports/*.jsonl` — optional normalized JSONL token usage events (`{"provider":"antigravity","model":"gemini-4-neon","timestamp":"...","input_tokens":1000,"output_tokens":300,"cache_read_tokens":400}`).

---

## Roadmap (Phase 2)

- Safe isolated-directory multi-account switching (`⇄ Switch`) for Claude Code (`CLAUDE_CONFIG_DIR`) & Codex CLI (`CODEX_HOME`) with pre-switch credential snapshot write-back.
- Optional one-click LiteLLM pricing table sync.
- Menu bar alert thresholds & macOS notifications when burn pace exceeds quota budget.
- Homebrew Cask distribution.

---

## License

Licensed under the **GNU General Public License v3.0** (`GPL-3.0`). See [LICENSE](LICENSE) for full terms.
