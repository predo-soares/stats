import Foundation

@main
struct RunUsageCostingSelfChecks {
    static func main() {
        let catalog = PricingCatalog(revision: "fixture", rates: [
            "gpt-test": ModelPricing(inputPerMillion: 1, cacheReadPerMillion: 0.5, cacheWritePerMillion: 2, outputPerMillion: 3)
        ])
        let result = UsageCosting(catalog: catalog).estimate([
            PricingTokenUsage(model: "gpt-test", inputTokens: 1_000_000, cacheReadTokens: 2_000_000, cacheWriteTokens: 0, outputTokens: 1_000_000),
            PricingTokenUsage(model: "unknown", inputTokens: 100, cacheReadTokens: 0, cacheWriteTokens: 0, outputTokens: 100)
        ])
        guard abs(result.estimate.pricedCost - 5) < 0.0001 else { fatalError("known model valuation mismatch") }
        guard result.estimate.unpricedTokens == 200, !result.isComplete else { fatalError("unknown model was not marked incomplete") }
        print("PASS: usage costing aggregation checks")
    }
}
