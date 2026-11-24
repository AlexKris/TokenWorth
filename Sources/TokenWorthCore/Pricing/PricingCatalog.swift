import Foundation

public struct PricingCatalog: Sendable {
    public private(set) var modelsByID: [String: ModelPricing]
    private var normalizedIndex: [String: ModelPricing]

    public static let `default` = PricingCatalog()

    public init(
        builtIn: [ModelPricing] = PricingCatalog.defaultModels,
        overrides: [ModelPricing] = []
    ) {
        var map: [String: ModelPricing] = [:]
        for item in builtIn {
            map[item.modelID.lowercased()] = item
        }
        for item in overrides {
            map[item.modelID.lowercased()] = item
        }
        self.modelsByID = map

        var normalized: [String: ModelPricing] = [:]
        for (key, value) in map {
            normalized[Self.normalizeDelimiters(key)] = value
        }
        self.normalizedIndex = normalized
    }

    public static func loadWithOverrides(customPath: String? = nil) -> PricingCatalog {
        let candidateURLs: [URL] = [
            customPath.map { URL(fileURLWithPath: AppPaths.expandTilde($0)) },
            AppPaths.pricingOverridesFile
        ].compactMap { $0 }

        var overrides: [ModelPricing] = []
        let decoder = JSONDecoder()
        for url in candidateURLs {
            guard FileManager.default.fileExists(atPath: url.path),
                  let data = try? Data(contentsOf: url) else {
                continue
            }
            if let list = try? decoder.decode([ModelPricing].self, from: data) {
                overrides.append(contentsOf: list)
            } else if let dict = try? decoder.decode([String: ModelPricing].self, from: data) {
                overrides.append(contentsOf: dict.values)
            } else if let liteLLM = try? parseLiteLLMPricing(data: data) {
                overrides.append(contentsOf: liteLLM)
            }
        }
        return PricingCatalog(builtIn: defaultModels, overrides: overrides)
    }

    public var allModels: [ModelPricing] {
        modelsByID.values.sorted {
            if $0.provider != $1.provider {
                return $0.provider.rawValue < $1.provider.rawValue
            }
            return $0.modelID < $1.modelID
        }
    }

    public func resolve(modelName: String) -> ModelPricing? {
        let cleaned = Self.cleanModelName(modelName)
        guard !cleaned.isEmpty else { return nil }

        if let exact = modelsByID[cleaned] {
            return exact
        }

        let normalized = Self.normalizeDelimiters(cleaned)
        if let normMatch = normalizedIndex[normalized] {
            return normMatch
        }

        // Longest boundary-safe prefix match across both raw and delimiter-normalized forms.
        let sortedCandidates = modelsByID.keys.sorted { $0.count > $1.count }
        for key in sortedCandidates {
            if Self.matchesPrefixWithBoundary(cleaned, prefix: key), let pricing = modelsByID[key] {
                return pricing
            }
            let normKey = Self.normalizeDelimiters(key)
            if Self.matchesPrefixWithBoundary(normalized, prefix: normKey), let pricing = normalizedIndex[normKey] {
                return pricing
            }
        }

        return nil
    }

    public func search(query: String?) -> [ModelPricing] {
        guard let query = query?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !query.isEmpty else {
            return allModels
        }
        return allModels.filter {
            $0.modelID.lowercased().contains(query) ||
            $0.provider.displayName.lowercased().contains(query)
        }
    }

    // MARK: - LiteLLM JSON Support

    private struct LiteLLMEntry: Decodable {
        let input_cost_per_token: Double?
        let output_cost_per_token: Double?
        let cache_read_input_token_cost: Double?
        let cache_creation_input_token_cost: Double?
        let litellm_provider: String?
    }

    public static func parseLiteLLMPricing(data: Data) throws -> [ModelPricing] {
        let raw = try JSONDecoder().decode([String: LiteLLMEntry].self, from: data)
        var parsed: [ModelPricing] = []
        for (rawKey, entry) in raw {
            guard let inCost = entry.input_cost_per_token,
                  let outCost = entry.output_cost_per_token,
                  let provider = inferProvider(modelID: rawKey, liteLLMProvider: entry.litellm_provider) else {
                continue
            }
            let modelID = cleanModelName(rawKey)
            parsed.append(
                ModelPricing(
                    modelID: modelID,
                    provider: provider,
                    inputPerMillion: inCost * 1_000_000.0,
                    outputPerMillion: outCost * 1_000_000.0,
                    cacheReadPerMillion: entry.cache_read_input_token_cost.map { $0 * 1_000_000.0 },
                    cacheWritePerMillion: entry.cache_creation_input_token_cost.map { $0 * 1_000_000.0 }
                )
            )
        }
        return parsed
    }

    public static func fetchLiteLLMPricing(
        session: URLSession = .shared,
        url: URL = URL(string: "https://raw.githubusercontent.com/BerriAI/litellm/main/model_prices_and_context_window.json")!
    ) async throws -> [ModelPricing] {
        let (data, _) = try await session.data(from: url)
        return try parseLiteLLMPricing(data: data)
    }

    private static func inferProvider(modelID: String, liteLLMProvider: String?) -> ProviderID? {
        let lower = modelID.lowercased()
        let prov = (liteLLMProvider ?? "").lowercased()
        if lower.contains("claude") || prov.contains("anthropic") {
            return .claude
        }
        if lower.hasPrefix("gpt-") || lower.hasPrefix("o1") || lower.hasPrefix("o3") || lower.hasPrefix("o4") || lower.contains("codex") || prov.contains("openai") {
            return .codex
        }
        if lower.contains("gemini") || prov.contains("gemini") || prov.contains("google") {
            return .antigravity
        }
        if lower.contains("grok") || prov.contains("xai") {
            return .grok
        }
        return nil
    }

    // MARK: - Normalization Helpers

    static func cleanModelName(_ raw: String) -> String {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        let prefixes = ["anthropic/", "openai/", "google/", "xai/", "x-ai/", "models/"]
        for prefix in prefixes where value.hasPrefix(prefix) {
            value = String(value.dropFirst(prefix.count))
        }

        if let atIdx = value.firstIndex(of: "@") {
            value = String(value[..<atIdx])
        }

        if value.hasSuffix("-latest") {
            value = String(value.dropLast("-latest".count))
        }

        // Strip trailing -YYYYMMDD date stamp if present.
        if let dashRange = value.range(of: #"-\d{8}$"#, options: .regularExpression) {
            value.removeSubrange(dashRange)
        }

        return value
    }

    private static func normalizeDelimiters(_ value: String) -> String {
        value.replacingOccurrences(of: ".", with: "-")
            .replacingOccurrences(of: "_", with: "-")
    }

    private static func matchesPrefixWithBoundary(_ text: String, prefix: String) -> Bool {
        guard text.hasPrefix(prefix) else { return false }
        if text.count == prefix.count { return true }
        let nextChar = text[text.index(text.startIndex, offsetBy: prefix.count)]
        return nextChar == "-" || nextChar == "." || nextChar == "_" || nextChar == ":"
    }

    // MARK: - Built-In Official Pricing Catalog (USD per 1M tokens)

    public static let defaultModels: [ModelPricing] = [
        // Anthropic Claude
        ModelPricing(modelID: "claude-fable-5-2", provider: .claude, inputPerMillion: 8.00, outputPerMillion: 40.00, cacheReadPerMillion: 0.20, cacheWritePerMillion: 10.00),
        ModelPricing(modelID: "claude-opus-5-5", provider: .claude, inputPerMillion: 4.00, outputPerMillion: 20.00, cacheReadPerMillion: 0.20, cacheWritePerMillion: 5.00),
        ModelPricing(modelID: "claude-sonnet-5-5", provider: .claude, inputPerMillion: 2.00, outputPerMillion: 10.00, cacheReadPerMillion: 0.10, cacheWritePerMillion: 2.50),
        ModelPricing(modelID: "claude-haiku-5-5", provider: .claude, inputPerMillion: 0.10, outputPerMillion: 0.50, cacheReadPerMillion: 0.01, cacheWritePerMillion: 0.125, longContextThreshold: 100_000, longContextInputMultiplier: 5.0, longContextOutputMultiplier: 5.0),
        ModelPricing(modelID: "claude-opus-4-6", provider: .claude, inputPerMillion: 5.00, outputPerMillion: 25.00, cacheReadPerMillion: 0.50, cacheWritePerMillion: 6.25),
        ModelPricing(modelID: "claude-opus-4-5", provider: .claude, inputPerMillion: 5.00, outputPerMillion: 25.00, cacheReadPerMillion: 0.50, cacheWritePerMillion: 6.25),
        ModelPricing(modelID: "claude-sonnet-4-6", provider: .claude, inputPerMillion: 3.00, outputPerMillion: 15.00, cacheReadPerMillion: 0.30, cacheWritePerMillion: 3.75),
        ModelPricing(modelID: "claude-sonnet-4-5", provider: .claude, inputPerMillion: 3.00, outputPerMillion: 15.00, cacheReadPerMillion: 0.30, cacheWritePerMillion: 3.75),
        ModelPricing(modelID: "claude-haiku-4-5", provider: .claude, inputPerMillion: 1.00, outputPerMillion: 5.00, cacheReadPerMillion: 0.10, cacheWritePerMillion: 1.25),
        ModelPricing(modelID: "claude-opus-4", provider: .claude, inputPerMillion: 15.00, outputPerMillion: 75.00, cacheReadPerMillion: 1.50, cacheWritePerMillion: 18.75),
        ModelPricing(modelID: "claude-sonnet-4", provider: .claude, inputPerMillion: 3.00, outputPerMillion: 15.00, cacheReadPerMillion: 0.30, cacheWritePerMillion: 3.75),
        ModelPricing(modelID: "claude-3-7-sonnet", provider: .claude, inputPerMillion: 3.00, outputPerMillion: 15.00, cacheReadPerMillion: 0.30, cacheWritePerMillion: 3.75),
        ModelPricing(modelID: "claude-3-5-sonnet", provider: .claude, inputPerMillion: 3.00, outputPerMillion: 15.00, cacheReadPerMillion: 0.30, cacheWritePerMillion: 3.75),
        ModelPricing(modelID: "claude-3-5-haiku", provider: .claude, inputPerMillion: 0.80, outputPerMillion: 4.00, cacheReadPerMillion: 0.08, cacheWritePerMillion: 1.00),

        // OpenAI / Codex
        ModelPricing(modelID: "gpt-6.2-astra", provider: .codex, inputPerMillion: 8.00, outputPerMillion: 40.00, cacheReadPerMillion: 0.40, cacheWritePerMillion: 8.00),
        ModelPricing(modelID: "gpt-6.2-sol", provider: .codex, inputPerMillion: 2.00, outputPerMillion: 10.00, cacheReadPerMillion: 0.10, cacheWritePerMillion: 2.00),
        ModelPricing(modelID: "gpt-6.1-sol", provider: .codex, inputPerMillion: 2.00, outputPerMillion: 10.00, cacheReadPerMillion: 0.10, cacheWritePerMillion: 2.00, longContextThreshold: 272_000, longContextInputMultiplier: 2.0, longContextOutputMultiplier: 1.5),
        ModelPricing(modelID: "gpt-6.1-terra", provider: .codex, inputPerMillion: 1.00, outputPerMillion: 5.00, cacheReadPerMillion: 0.05, cacheWritePerMillion: 1.00, longContextThreshold: 272_000, longContextInputMultiplier: 2.0, longContextOutputMultiplier: 1.5),
        ModelPricing(modelID: "gpt-6-astra", provider: .codex, inputPerMillion: 10.00, outputPerMillion: 50.00, cacheReadPerMillion: 1.00, cacheWritePerMillion: 10.00),
        ModelPricing(modelID: "gpt-6-luna", provider: .codex, inputPerMillion: 0.10, outputPerMillion: 0.50, cacheReadPerMillion: 0.01, cacheWritePerMillion: 0.10),
        ModelPricing(modelID: "gpt-5.5", provider: .codex, inputPerMillion: 5.00, outputPerMillion: 30.00, cacheReadPerMillion: 0.50, cacheWritePerMillion: 5.00),
        ModelPricing(modelID: "gpt-5.4", provider: .codex, inputPerMillion: 2.50, outputPerMillion: 15.00, cacheReadPerMillion: 0.25, cacheWritePerMillion: 2.50),
        ModelPricing(modelID: "gpt-5.3-codex", provider: .codex, inputPerMillion: 1.75, outputPerMillion: 14.00, cacheReadPerMillion: 0.175, cacheWritePerMillion: 1.75),
        ModelPricing(modelID: "gpt-5.2-codex", provider: .codex, inputPerMillion: 1.75, outputPerMillion: 14.00, cacheReadPerMillion: 0.175, cacheWritePerMillion: 1.75),
        ModelPricing(modelID: "gpt-5.2", provider: .codex, inputPerMillion: 1.75, outputPerMillion: 14.00, cacheReadPerMillion: 0.175, cacheWritePerMillion: 1.75),
        ModelPricing(modelID: "gpt-5.1-codex", provider: .codex, inputPerMillion: 1.25, outputPerMillion: 10.00, cacheReadPerMillion: 0.125, cacheWritePerMillion: 1.25),
        ModelPricing(modelID: "gpt-5-codex", provider: .codex, inputPerMillion: 1.25, outputPerMillion: 10.00, cacheReadPerMillion: 0.125, cacheWritePerMillion: 1.25),
        ModelPricing(modelID: "gpt-5", provider: .codex, inputPerMillion: 1.25, outputPerMillion: 10.00, cacheReadPerMillion: 0.125, cacheWritePerMillion: 1.25),
        ModelPricing(modelID: "gpt-5-mini", provider: .codex, inputPerMillion: 0.25, outputPerMillion: 2.00, cacheReadPerMillion: 0.025, cacheWritePerMillion: 0.25),
        ModelPricing(modelID: "gpt-5-nano", provider: .codex, inputPerMillion: 0.05, outputPerMillion: 0.40, cacheReadPerMillion: 0.005, cacheWritePerMillion: 0.05),
        ModelPricing(modelID: "gpt-4.1", provider: .codex, inputPerMillion: 2.00, outputPerMillion: 8.00, cacheReadPerMillion: 0.50, cacheWritePerMillion: 2.00),
        ModelPricing(modelID: "gpt-4.1-mini", provider: .codex, inputPerMillion: 0.40, outputPerMillion: 1.60, cacheReadPerMillion: 0.10, cacheWritePerMillion: 0.40),
        ModelPricing(modelID: "gpt-4o", provider: .codex, inputPerMillion: 2.50, outputPerMillion: 10.00, cacheReadPerMillion: 1.25, cacheWritePerMillion: 2.50),
        ModelPricing(modelID: "gpt-4o-mini", provider: .codex, inputPerMillion: 0.15, outputPerMillion: 0.60, cacheReadPerMillion: 0.075, cacheWritePerMillion: 0.15),
        ModelPricing(modelID: "o3", provider: .codex, inputPerMillion: 2.00, outputPerMillion: 8.00, cacheReadPerMillion: 0.50, cacheWritePerMillion: 2.00),
        ModelPricing(modelID: "o4-mini", provider: .codex, inputPerMillion: 1.10, outputPerMillion: 4.40, cacheReadPerMillion: 0.275, cacheWritePerMillion: 1.10),

        // Google Gemini (Antigravity / Gemini CLI)
        ModelPricing(modelID: "gemini-4-neon", provider: .antigravity, inputPerMillion: 3.00, outputPerMillion: 15.00, cacheReadPerMillion: 0.15, cacheWritePerMillion: 3.00),
        ModelPricing(modelID: "gemini-4-argon", provider: .antigravity, inputPerMillion: 4.00, outputPerMillion: 20.00, cacheReadPerMillion: 0.20, cacheWritePerMillion: 4.00),
        ModelPricing(modelID: "gemini-4-carbon", provider: .antigravity, inputPerMillion: 2.00, outputPerMillion: 10.00, cacheReadPerMillion: 0.10, cacheWritePerMillion: 2.00),
        ModelPricing(modelID: "gemini-4-hydrogen", provider: .antigravity, inputPerMillion: 1.50, outputPerMillion: 7.50, cacheReadPerMillion: 0.075, cacheWritePerMillion: 1.50),
        ModelPricing(modelID: "gemini-3.8-flash", provider: .antigravity, inputPerMillion: 0.75, outputPerMillion: 3.75, cacheReadPerMillion: 0.075, cacheWritePerMillion: 0.75),
        ModelPricing(modelID: "gemini-3.5-flash-lite", provider: .antigravity, inputPerMillion: 0.30, outputPerMillion: 2.50, cacheReadPerMillion: 0.03, cacheWritePerMillion: 0.30),
        ModelPricing(modelID: "gemini-3-pro", provider: .antigravity, inputPerMillion: 2.00, outputPerMillion: 12.00, cacheReadPerMillion: 0.20, cacheWritePerMillion: 2.00),
        ModelPricing(modelID: "gemini-3-flash", provider: .antigravity, inputPerMillion: 0.50, outputPerMillion: 3.00, cacheReadPerMillion: 0.05, cacheWritePerMillion: 0.50),
        ModelPricing(modelID: "gemini-2.5-pro", provider: .antigravity, inputPerMillion: 1.25, outputPerMillion: 10.00, cacheReadPerMillion: 0.125, cacheWritePerMillion: 1.25, longContextThreshold: 200_000, longContextInputMultiplier: 2.0, longContextOutputMultiplier: 1.5),
        ModelPricing(modelID: "gemini-2.5-flash", provider: .antigravity, inputPerMillion: 0.30, outputPerMillion: 2.50, cacheReadPerMillion: 0.03, cacheWritePerMillion: 0.30),
        ModelPricing(modelID: "gemini-2.5-flash-lite", provider: .antigravity, inputPerMillion: 0.10, outputPerMillion: 0.40, cacheReadPerMillion: 0.01, cacheWritePerMillion: 0.10),

        // xAI Grok
        ModelPricing(modelID: "grok-4.7", provider: .grok, inputPerMillion: 2.00, outputPerMillion: 6.00, cacheReadPerMillion: 0.50, cacheWritePerMillion: 2.00, longContextThreshold: 200_000, longContextInputMultiplier: 2.0, longContextOutputMultiplier: 2.0),
        ModelPricing(modelID: "grok-4.6", provider: .grok, inputPerMillion: 2.00, outputPerMillion: 6.00, cacheReadPerMillion: 0.50, cacheWritePerMillion: 2.00, longContextThreshold: 200_000, longContextInputMultiplier: 2.0, longContextOutputMultiplier: 2.0),
        ModelPricing(modelID: "grok-4.3", provider: .grok, inputPerMillion: 1.25, outputPerMillion: 2.50, cacheReadPerMillion: 0.20, cacheWritePerMillion: 1.25, longContextThreshold: 200_000, longContextInputMultiplier: 2.0, longContextOutputMultiplier: 2.0),
        ModelPricing(modelID: "grok-4.20", provider: .grok, inputPerMillion: 1.25, outputPerMillion: 2.50, cacheReadPerMillion: 0.20, cacheWritePerMillion: 1.25, longContextThreshold: 200_000, longContextInputMultiplier: 2.0, longContextOutputMultiplier: 2.0),
        ModelPricing(modelID: "grok-4", provider: .grok, inputPerMillion: 3.00, outputPerMillion: 15.00, cacheReadPerMillion: 0.75, cacheWritePerMillion: 3.00),
        ModelPricing(modelID: "grok-4-fast", provider: .grok, inputPerMillion: 0.20, outputPerMillion: 0.50, cacheReadPerMillion: 0.05, cacheWritePerMillion: 0.20),
        ModelPricing(modelID: "grok-build-0.1", provider: .grok, inputPerMillion: 1.00, outputPerMillion: 2.00, cacheReadPerMillion: 0.20, cacheWritePerMillion: 1.00),
        ModelPricing(modelID: "grok-code-fast", provider: .grok, inputPerMillion: 0.20, outputPerMillion: 1.50, cacheReadPerMillion: 0.02, cacheWritePerMillion: 0.20),
        ModelPricing(modelID: "grok-3", provider: .grok, inputPerMillion: 3.00, outputPerMillion: 15.00, cacheReadPerMillion: 0.75, cacheWritePerMillion: 3.00),
        ModelPricing(modelID: "grok-3-mini", provider: .grok, inputPerMillion: 0.30, outputPerMillion: 0.50, cacheReadPerMillion: 0.075, cacheWritePerMillion: 0.30)
    ]
}
