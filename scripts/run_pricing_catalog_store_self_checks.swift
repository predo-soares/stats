import Foundation

@main
struct RunPricingCatalogStoreSelfChecks {
    static func main() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "stats-pricing-(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = PricingCatalogStore(directory: directory)
        let valid = PricingCatalog(revision: "fixture-1", publishedAt: Date(timeIntervalSince1970: 1), rates: ["model-a": ModelPricing(inputPerMillion: 1, cacheReadPerMillion: 0.1, cacheWritePerMillion: nil, outputPerMillion: 2)])
        try store.save(valid)
        precondition(store.load() == valid)
        do {
            try store.save(PricingCatalog(revision: "", rates: [:]))
            preconditionFailure("invalid catalog was persisted")
        } catch PricingCatalogError.invalidCatalog { }
        precondition(store.load() == valid)
        print("PASS: pricing catalog persistence and invalid replacement checks")
    }
}
