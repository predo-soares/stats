import Foundation

struct UsageCostResult: Sendable, Equatable {
    let estimate: CostEstimate
    let catalogRevision: String
    let usageRecords: Int

    var isComplete: Bool { estimate.isComplete }
}

struct UsageCosting: Sendable {
    let catalog: PricingCatalog

    func estimate(_ usage: [PricingTokenUsage]) -> UsageCostResult {
        let total = usage.reduce(into: CostEstimate(pricedCost: 0, pricedTokens: 0, unpricedTokens: 0, unpricedModels: [])) { result, item in
            result = result + catalog.estimate(item)
        }
        return UsageCostResult(estimate: total, catalogRevision: catalog.revision, usageRecords: usage.count)
    }
}
