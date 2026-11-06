import Foundation

@main
struct RunZaiUsageSelfChecks {
    static func main() async {
        var failures: [String] = []
        await checkFixture(failures: &failures)
        if failures.isEmpty {
            print("PASS: Z.ai fixture-to-ledger checks")
        } else {
            failures.forEach { print("FAIL: \($0)") }
            exit(1)
        }
    }

    private static func checkFixture(failures: inout [String]) async {
        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: "stats/Features/Usage/Fixtures/zai-usage.fixture.json"))
            let events = try ZaiUsageImporter().parseBundle(data)
            guard events.count == 2 else {
                failures.append("expected 2 zai model rows, got \(events.count)")
                return
            }
            let total = events.reduce(0) { $0 + $1.totalTokens }
            guard total == 1_850_000 else {
                failures.append("unexpected zai total \(total)")
                return
            }
            do {
                _ = try ZaiUsageImporter().importEvents(usingCredentialPresent: false)
                failures.append("missing credential must fail import")
                return
            } catch ZaiUsageImporter.ImportError.sourceMissing {
                // expected
            } catch {
                failures.append("missing credential threw unexpected \(error)")
                return
            }
            let root = FileManager.default.temporaryDirectory.appending(path: "stats-zai-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: root) }
            let ledger = try CodexUsageLedger(directory: root)
            try await ledger.replaceLocal(provider: .zai, events: events)
            let allTime = try await ledger.local(
                provider: .zai,
                range: UsageDateRange(start: Date(timeIntervalSince1970: 0), end: Date(timeIntervalSince1970: 2_000_000_000))
            )
            guard allTime.records == 2, allTime.totalTokens == 1_850_000 else {
                failures.append("zai ledger projection failed (\(allTime.records)/\(allTime.totalTokens))")
                return
            }
            let evidence = try await ledger.localSourceEvidence(
                provider: .zai,
                requestedWindowLabel: "All",
                range: UsageDateRange(start: Date(timeIntervalSince1970: 0), end: Date(timeIntervalSince1970: 2_000_000_000)),
                outcome: .imported,
                safeErrorReason: nil
            )
            guard evidence.provider == .zai, evidence.eventCount == 2 else {
                failures.append("zai source evidence failed")
                return
            }
            let cost = UsageCosting(catalog: PricingCatalog(revision: "empty", rates: [:])).estimate(events.map { $0.pricingUsage() })
            guard !cost.isComplete else {
                failures.append("unpriced zai models must leave estimate incomplete")
                return
            }
            for event in events {
                let mirror = Mirror(reflecting: event)
                let blob = mirror.children.map { "\($0.label ?? ""):\($0.value)" }.joined(separator: "|").lowercased()
                if blob.contains("fixture-zai-key") || blob.contains("api-key") || blob.contains("authorization") {
                    failures.append("credential material leaked into LocalUsageEvent")
                    return
                }
            }
        } catch {
            failures.append("zai check failed: \(error)")
        }
    }
}
