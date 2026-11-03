import Foundation

/// Token counters normalized by the provider collectors before valuation.
struct PricingTokenUsage: Sendable, Equatable {
    let model: String?
    let inputTokens: Int
    let cacheReadTokens: Int
    let cacheWriteTokens: Int
    let outputTokens: Int

    var tokenCount: Int {
        inputTokens + cacheReadTokens + cacheWriteTokens + outputTokens
    }
}

/// API-rate inputs are expressed in currency units per one million tokens.
struct ModelPricing: Sendable, Equatable, Codable {
    let inputPerMillion: Double
    let cacheReadPerMillion: Double?
    let cacheWritePerMillion: Double?
    let outputPerMillion: Double
}

struct PricingCatalog: Sendable, Equatable, Codable {
    let revision: String
    let publishedAt: Date?
    fileprivate let rates: [String: ModelPricing]

    init(revision: String, publishedAt: Date? = nil, rates: [String: ModelPricing]) {
        self.revision = revision
        self.publishedAt = publishedAt
        self.rates = rates
    }

    var modelCount: Int { rates.count }

    func pricing(for model: String?) -> ModelPricing? {
        guard let model else { return nil }
        if let exact = rates[model] { return exact }
        let normalized = model.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        return rates.first { key, _ in key.lowercased() == normalized }?.value
    }

    func estimate(_ usage: PricingTokenUsage) -> CostEstimate {
        guard let rate = pricing(for: usage.model) else {
            return CostEstimate(pricedCost: 0, pricedTokens: 0, unpricedTokens: usage.tokenCount, unpricedModels: [usage.model ?? "Unknown model"])
        }

        var cost = Double(usage.inputTokens) * rate.inputPerMillion / 1_000_000
        var pricedTokens = usage.inputTokens
        var unpricedTokens = 0
        if let cacheRead = rate.cacheReadPerMillion {
            cost += Double(usage.cacheReadTokens) * cacheRead / 1_000_000
            pricedTokens += usage.cacheReadTokens
        } else { unpricedTokens += usage.cacheReadTokens }
        if let cacheWrite = rate.cacheWritePerMillion {
            cost += Double(usage.cacheWriteTokens) * cacheWrite / 1_000_000
            pricedTokens += usage.cacheWriteTokens
        } else { unpricedTokens += usage.cacheWriteTokens }
        cost += Double(usage.outputTokens) * rate.outputPerMillion / 1_000_000
        pricedTokens += usage.outputTokens
        return CostEstimate(pricedCost: cost, pricedTokens: pricedTokens, unpricedTokens: unpricedTokens, unpricedModels: unpricedTokens == 0 ? [] : [usage.model ?? "Unknown model"])
    }
}

/// Persists the last validated pricing table so estimates remain available offline.
struct PricingCatalogStore: Sendable {
    let url: URL

    init(directory: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appending(path: "stats", directoryHint: .isDirectory)) {
        self.url = directory.appending(path: "pricing-catalog.json")
    }

    func load() -> PricingCatalog? {
        guard let data = try? Data(contentsOf: url), let catalog = try? JSONDecoder().decode(PricingCatalog.self, from: data), Self.isValid(catalog) else { return nil }
        return catalog
    }

    func save(_ catalog: PricingCatalog) throws {
        guard Self.isValid(catalog) else { throw PricingCatalogError.invalidCatalog }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(catalog)
        try data.write(to: url, options: [.atomic])
    }

    func replaceIfValid(_ catalog: PricingCatalog) throws -> PricingCatalog {
        try save(catalog)
        return catalog
    }

    private static func isValid(_ catalog: PricingCatalog) -> Bool {
        !catalog.revision.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !catalog.rates.isEmpty && catalog.rates.values.allSatisfy { rate in
            rate.inputPerMillion >= 0 && rate.outputPerMillion >= 0 && (rate.cacheReadPerMillion ?? 0) >= 0 && (rate.cacheWritePerMillion ?? 0) >= 0
        }
    }
}

enum PricingCatalogError: Error { case invalidCatalog }

struct CostEstimate: Sendable, Equatable {
    let pricedCost: Double
    let pricedTokens: Int
    let unpricedTokens: Int
    let unpricedModels: [String]

    var isComplete: Bool { unpricedTokens == 0 && unpricedModels.isEmpty }

    static func + (lhs: CostEstimate, rhs: CostEstimate) -> CostEstimate {
        CostEstimate(
            pricedCost: lhs.pricedCost + rhs.pricedCost,
            pricedTokens: lhs.pricedTokens + rhs.pricedTokens,
            unpricedTokens: lhs.unpricedTokens + rhs.unpricedTokens,
            unpricedModels: Array(Set(lhs.unpricedModels + rhs.unpricedModels)).sorted()
        )
    }
}
