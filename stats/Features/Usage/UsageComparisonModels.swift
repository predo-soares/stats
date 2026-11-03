import Foundation

/// Dashboard windows use local-calendar arithmetic. Baselines are disjoint and end at the
/// same local time offset as the selected window, so an unfinished period is not compared with
/// a completed one.
enum UsageComparisonPeriod: String, CaseIterable, Sendable, Identifiable {
    case today
    case last7Days
    case last30Days

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: "Today"
        case .last7Days: "Last 7 Days"
        case .last30Days: "Last 30 Days"
        }
    }

    private var baselineDays: Int {
        switch self {
        case .today: 1
        case .last7Days: 7
        case .last30Days: 30
        }
    }

    private var spanDays: Int {
        switch self {
        case .today: 1
        case .last7Days: 7
        case .last30Days: 30
        }
    }

    func currentInterval(now: Date, calendar: Calendar = .current) -> DateInterval {
        let start = calendar.date(byAdding: .day, value: -(spanDays - 1), to: calendar.startOfDay(for: now)) ?? calendar.startOfDay(for: now)
        return DateInterval(start: start, end: now)
    }

    func baselineInterval(now: Date, calendar: Calendar = .current) -> DateInterval {
        let current = currentInterval(now: now, calendar: calendar)
        let start = calendar.date(byAdding: .day, value: -baselineDays, to: current.start) ?? current.start
        let end = calendar.date(byAdding: .day, value: -baselineDays, to: current.end) ?? current.end
        return DateInterval(start: start, end: end)
    }
}

enum UsageComparisonCoverage: Sendable, Equatable {
    case complete
    case incomplete(String)
    case unavailable(String)

    var isComplete: Bool {
        if case .complete = self { return true }
        return false
    }

    var label: String? {
        switch self {
        case .complete: nil
        case .incomplete(let message), .unavailable(let message): message
        }
    }
}

enum UsageComparisonOutcome: Sendable, Equatable {
    case percentage(Double)
    case noPreviousUsage
    case noChange
    case unavailable
}

struct UsageTokenComparison: Sendable, Equatable {
    let current: Int
    let baseline: Int?
    let difference: Int?
    let outcome: UsageComparisonOutcome
    let coverage: UsageComparisonCoverage

    static func make(current: Int, baseline: Int?, coverage: UsageComparisonCoverage) -> Self {
        guard coverage.isComplete, let baseline else {
            return Self(current: current, baseline: baseline, difference: nil, outcome: .unavailable, coverage: coverage)
        }

        let difference = current - baseline
        if baseline == 0 {
            return Self(current: current, baseline: baseline, difference: difference, outcome: current == 0 ? .noChange : .noPreviousUsage, coverage: coverage)
        }
        return Self(current: current, baseline: baseline, difference: difference, outcome: .percentage(Double(difference) / Double(baseline) * 100), coverage: coverage)
    }
}
