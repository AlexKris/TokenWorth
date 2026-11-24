import Foundation
import Testing
@testable import TokenWorthCore

@Suite("PricingCatalog & CostCalculator")
struct PricingCatalogTests {
    @Test("Resolves exact, prefixed, dated, and delimiter-variant model names")
    func resolvesModelVariants() {
        let catalog = PricingCatalog.default

        #expect(catalog.resolve(modelName: "claude-opus-4-6")?.inputPerMillion == 5.0)
        #expect(catalog.resolve(modelName: "anthropic/claude-sonnet-4-5-20250929")?.modelID == "claude-sonnet-4-5")
        #expect(catalog.resolve(modelName: "claude-sonnet-4.5")?.modelID == "claude-sonnet-4-5")
        #expect(catalog.resolve(modelName: "openai/gpt-5.3-codex-high")?.modelID == "gpt-5.3-codex")
        #expect(catalog.resolve(modelName: "models/gemini-2.5-pro")?.modelID == "gemini-2.5-pro")
        #expect(catalog.resolve(modelName: "xai/grok-4.7-20260201")?.modelID == "grok-4.7")
        #expect(catalog.resolve(modelName: "gpt-50-unknown") == nil)
    }

    @Test("Calculates standard cost, cache savings, and long-context multipliers")
    func calculatesCostAndSavings() {
        let calc = CostCalculator(catalog: .default)
        let tokens = TokenCounts(
            input: 100_000,
            output: 50_000,
            cacheRead: 500_000,
            cacheWrite: 20_000,
            reasoning: 10_000
        )

        let cost = calc.cost(for: tokens, modelName: "claude-sonnet-4-6")
        // Input: 0.1M * $3 = $0.30
        // Output: 0.05M * $15 = $0.75 (reasoning NOT billed twice)
        // CacheRead: 0.5M * $0.30 = $0.15
        // CacheWrite: 0.02M * $3.75 = $0.075
        // CacheSavings: 0.5M * ($3.00 - $0.30) = $1.35
        #expect(abs(cost.inputUSD - 0.30) < 0.0001)
        #expect(abs(cost.outputUSD - 0.75) < 0.0001)
        #expect(abs(cost.cacheReadUSD - 0.15) < 0.0001)
        #expect(abs(cost.cacheWriteUSD - 0.075) < 0.0001)
        #expect(abs(cost.totalUSD - 1.275) < 0.0001)
        #expect(abs(cost.cacheSavingsUSD - 1.35) < 0.0001)
        #expect(cost.isEstimatedOrUnpriced == false)

        // Gemini 2.5 Pro > 200K prompt applies 2.0x input & 1.5x output
        let longTokens = TokenCounts(input: 250_000, output: 100_000)
        let longCost = calc.cost(for: longTokens, modelName: "gemini-2.5-pro")
        #expect(abs(longCost.inputUSD - (0.25 * 1.25 * 2.0)) < 0.0001)
        #expect(abs(longCost.outputUSD - (0.10 * 10.0 * 1.5)) < 0.0001)

        // Unknown model flags unpriced
        let unknownCost = calc.cost(for: tokens, modelName: "totally-unknown-model")
        #expect(unknownCost.isEstimatedOrUnpriced == true)
        #expect(unknownCost.totalUSD == 0)
    }

    @Test("Parses LiteLLM pricing JSON format")
    func parsesLiteLLMJSON() throws {
        let json = """
        {
          "anthropic/claude-custom-test": {
            "input_cost_per_token": 0.000003,
            "output_cost_per_token": 0.000015,
            "cache_read_input_token_cost": 0.0000003,
            "litellm_provider": "anthropic"
          }
        }
        """.data(using: .utf8)!

        let parsed = try PricingCatalog.parseLiteLLMPricing(data: json)
        #expect(parsed.count == 1)
        #expect(parsed[0].modelID == "claude-custom-test")
        #expect(parsed[0].provider == .claude)
        #expect(abs(parsed[0].inputPerMillion - 3.0) < 0.0001)
        #expect(abs(parsed[0].cacheReadPerMillion - 0.3) < 0.0001)
    }
}
