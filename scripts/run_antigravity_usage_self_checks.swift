import Foundation

@main
struct RunAntigravityUsageSelfChecks {
    static func main() async {
        var failures: [String] = []
        await checkFixture(failures: &failures)
        if failures.isEmpty {
            print("PASS: Antigravity fixture-to-ledger checks")
        } else {
            failures.forEach { print("FAIL: \($0)") }
            exit(1)
        }
    }

    private static func checkFixture(failures: inout [String]) async {
        let root = FileManager.default.temporaryDirectory.appending(path: "stats-ag-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            try FileManager.default.copyItem(
                at: URL(fileURLWithPath: "stats/Features/Usage/Fixtures/antigravity-session.fixture.jsonl"),
                to: root.appending(path: "antigravity-session.fixture.jsonl")
            )
            let importer = AntigravityUsageImporter(snapshotsURL: root)
            let events = try importer.importEvents()
            guard events.count == 1 else {
                failures.append("expected 1 latest-per-session event, got \(events.count)")
                return
            }
            guard events[0].totalTokens == 27_800 else {
                failures.append("unexpected antigravity total \(events[0].totalTokens)")
                return
            }
            // workspaceLabel must not be retained on the event.
            let blob = Mirror(reflecting: events[0]).children.map { "\($0.label ?? ""):\($0.value)" }.joined(separator: "|").lowercased()
            if blob.contains("fixture-workspace") || blob.contains("workspace") {
                failures.append("workspace label leaked into LocalUsageEvent")
                return
            }
            let ledger = try CodexUsageLedger(directory: root.appending(path: "ledger"))
            try await ledger.replaceLocal(provider: .antigravity, events: events)
            let allTime = try await ledger.local(
                provider: .antigravity,
                range: UsageDateRange(start: Date(timeIntervalSince1970: 0), end: Date(timeIntervalSince1970: 2_000_000_000))
            )
            guard allTime.records == 1, allTime.totalTokens == 27_800 else {
                failures.append("antigravity ledger projection failed (\(allTime.records)/\(allTime.totalTokens))")
                return
            }
            let evidence = try await ledger.localSourceEvidence(
                provider: .antigravity,
                requestedWindowLabel: "All",
                range: UsageDateRange(start: Date(timeIntervalSince1970: 0), end: Date(timeIntervalSince1970: 2_000_000_000)),
                outcome: .imported,
                safeErrorReason: nil
            )
            guard evidence.provider == .antigravity, evidence.eventCount == 1 else {
                failures.append("antigravity source evidence failed")
                return
            }
            let cost = UsageCosting(catalog: PricingCatalog(revision: "empty", rates: [:])).estimate(events.map { $0.pricingUsage() })
            guard !cost.isComplete else {
                failures.append("unpriced antigravity models must leave estimate incomplete")
                return
            }
        } catch {
            failures.append("antigravity check failed: \(error)")
        }
    }
}
