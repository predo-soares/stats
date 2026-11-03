import Foundation

@main
struct RunUsageTrendSelfChecks {
    static func main() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "stats-ledger-trend-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let ledger = try CodexUsageLedger(directory: directory)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let hour = calendar.dateInterval(of: .hour, for: start)!.start
        let nextHour = calendar.date(byAdding: .hour, value: 1, to: hour)!
        try ledger.upsert([
            CodexUsageEvent(identifier: "a", timestamp: hour.addingTimeInterval(5), inputTokens: 10, cachedInputTokens: 2, outputTokens: 1, sourceFile: "fixture", model: "gpt-a"),
            CodexUsageEvent(identifier: "b", timestamp: hour.addingTimeInterval(20), inputTokens: 20, cachedInputTokens: 0, outputTokens: 2, sourceFile: "fixture", model: "gpt-a"),
            CodexUsageEvent(identifier: "c", timestamp: nextHour.addingTimeInterval(5), inputTokens: 4, cachedInputTokens: 0, outputTokens: 1, sourceFile: "fixture", model: "gpt-b")
        ])
        let range = UsageDateRange(start: hour, end: calendar.date(byAdding: .hour, value: 2, to: hour)!)
        let trend = try ledger.trend(range: range, granularity: .hourly, calendar: calendar)
        precondition(trend.count == 2 && trend[0].totalTokens == 35 && trend[0].records == 2 && trend[1].totalTokens == 5, "hourly trend buckets were incorrect")
        let models = try ledger.modelTotals(range: range)
        precondition(models.map(\.model) == ["gpt-a", "gpt-b"] && models[0].totalTokens == 35, "model totals were incorrect")
        print("PASS: usage trend and model breakdown checks")
    }
}
