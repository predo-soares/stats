import Foundation

@main
struct RunPricingSelfChecks {
    static func main() {
        let catalog = PricingCatalog(
            revision: "fixture-1",
            rates: ["model-a": ModelPricing(inputPerMillion: 1, cacheReadPerMillion: 0.1, cacheWritePerMillion: nil, outputPerMillion: 2)]
        )
        let known = catalog.estimate(PricingTokenUsage(model: "MODEL-A", inputTokens: 1_000_000, cacheReadTokens: 2_000_000, cacheWriteTokens: 3, outputTokens: 500_000))
        precondition(abs(known.pricedCost - 2.2) < 0.0001)
        precondition(known.unpricedTokens == 3)
        precondition(!known.isComplete)

        let unknown = catalog.estimate(PricingTokenUsage(model: "cursor-auto", inputTokens: 4, cacheReadTokens: 5, cacheWriteTokens: 6, outputTokens: 7))
        precondition(unknown.pricedCost == 0)
        precondition(unknown.pricedTokens == 0)
        precondition(unknown.unpricedTokens == 22)
        precondition(unknown.unpricedModels == ["cursor-auto"])
        print("PASS: pricing catalog and unknown-rate checks")
    }
}
