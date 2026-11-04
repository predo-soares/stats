import Foundation

@main
struct RunUsageLedgerRangeSelfChecks {
    static func main() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "stats-ledger-range-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let ledger = try CodexUsageLedger(directory: directory)
        let calendar = Calendar(identifier: .gregorian)
        let day = Date(timeIntervalSince1970: 1_700_000_000)
        let boundary = calendar.date(byAdding: .day, value: 1, to: day)!
        try await ledger.upsert([
            CodexUsageEvent(identifier: "before", timestamp: day.addingTimeInterval(10), inputTokens: 10, cachedInputTokens: 2, outputTokens: 1, sourceFile: "fixture"),
            CodexUsageEvent(identifier: "boundary", timestamp: boundary, inputTokens: 100, cachedInputTokens: 20, outputTokens: 10, sourceFile: "fixture")
        ])

        let first = try await ledger.codex(range: UsageDateRange(start: day, end: boundary))
        precondition(first.totalTokens == 13, "first range included an adjacent boundary")
        let second = try await ledger.codex(range: UsageDateRange(start: boundary, end: boundary.addingTimeInterval(86_400)))
        precondition(second.totalTokens == 130, "second range omitted its boundary event")
        print("PASS: usage ledger range boundaries are disjoint")
    }
}
