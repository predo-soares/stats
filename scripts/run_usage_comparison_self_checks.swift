import Foundation

@main
struct RunUsageComparisonSelfChecks {
    static func main() {
        var failures: [String] = []
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Sao_Paulo")!
        let now = ISO8601DateFormatter().date(from: "2026-11-03T15:20:00Z")!

        let today = UsageComparisonPeriod.today
        let todayCurrent = today.currentInterval(now: now, calendar: calendar)
        let todayBaseline = today.baselineInterval(now: now, calendar: calendar)
        if calendar.dateComponents([.day], from: todayBaseline.start, to: todayCurrent.start).day != 1 { failures.append("today baseline is not the preceding day") }
        if abs(todayBaseline.duration - todayCurrent.duration) > 0.001 { failures.append("today windows do not have equal elapsed duration") }

        let seven = UsageComparisonPeriod.last7Days
        let sevenCurrent = seven.currentInterval(now: now, calendar: calendar)
        let sevenBaseline = seven.baselineInterval(now: now, calendar: calendar)
        if sevenCurrent.start <= sevenBaseline.end { failures.append("7-day windows overlap") }
        if calendar.dateComponents([.day], from: sevenBaseline.end, to: sevenCurrent.end).day != 7 { failures.append("7-day baseline is not aligned") }

        let percentage = UsageTokenComparison.make(current: 150, baseline: 100, coverage: .complete)
        if percentage.outcome != .percentage(50) || percentage.difference != 50 { failures.append("percentage comparison is incorrect") }
        let zero = UsageTokenComparison.make(current: 20, baseline: 0, coverage: .complete)
        if zero.outcome != .noPreviousUsage || zero.difference != 20 { failures.append("zero-baseline comparison is incorrect") }
        let incomplete = UsageTokenComparison.make(current: 20, baseline: nil, coverage: .incomplete("Missing baseline history"))
        if incomplete.outcome != .unavailable || incomplete.difference != nil { failures.append("incomplete comparison was published") }

        if failures.isEmpty { print("PASS: usage comparison period and outcome checks") }
        else { print("FAIL: \(failures.joined(separator: "; "))"); Foundation.exit(1) }
    }
}
