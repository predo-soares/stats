import Foundation

@main
struct RunGrokUsageSelfChecks {
    static func main() async {
        var failures: [String] = []
        await checkFixture(failures: &failures)
        if failures.isEmpty {
            print("PASS: Grok fixture-to-ledger checks")
        } else {
            failures.forEach { print("FAIL: \($0)") }
            exit(1)
        }
    }

    private static func checkFixture(failures: inout [String]) async {
        let root = FileManager.default.temporaryDirectory.appending(path: "stats-grok-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            try FileManager.default.copyItem(
                at: URL(fileURLWithPath: "stats/Features/Usage/Fixtures/grok-session.fixture.jsonl"),
                to: root.appending(path: "grok-session.fixture.jsonl")
            )
            let importer = GrokUsageImporter(sessionsURL: root)
            let events = try importer.importEvents()
            // sess-001 uses transcript only (1350); sess-002 uses signals (5000)
            guard events.count == 2 else {
                failures.append("expected 2 grok events after signal/transcript preference, got \(events.count)")
                return
            }
            let total = events.reduce(0) { $0 + $1.totalTokens }
            guard total == 6350 else {
                failures.append("unexpected grok token total \(total)")
                return
            }
            let ledger = try CodexUsageLedger(directory: root.appending(path: "ledger"))
            try await ledger.replaceLocal(provider: .grok, events: events)
            let allTime = try await ledger.local(
                provider: .grok,
                range: UsageDateRange(start: Date(timeIntervalSince1970: 0), end: Date(timeIntervalSince1970: 2_000_000_000))
            )
            guard allTime.records == 2, allTime.totalTokens == 6350 else {
                failures.append("grok ledger projection failed (\(allTime.records)/\(allTime.totalTokens))")
                return
            }
            let evidence = try await ledger.localSourceEvidence(
                provider: .grok,
                requestedWindowLabel: "All",
                range: UsageDateRange(start: Date(timeIntervalSince1970: 0), end: Date(timeIntervalSince1970: 2_000_000_000)),
                outcome: .imported,
                safeErrorReason: nil
            )
            guard evidence.provider == .grok, evidence.eventCount == 2 else {
                failures.append("grok source evidence failed")
                return
            }
            let cost = UsageCosting(catalog: PricingCatalog(revision: "empty", rates: [:])).estimate(events.map { $0.pricingUsage() })
            guard !cost.isComplete else {
                failures.append("unpriced grok models must leave estimate incomplete")
                return
            }
        } catch {
            failures.append("grok check failed: \(error)")
        }
    }
}
