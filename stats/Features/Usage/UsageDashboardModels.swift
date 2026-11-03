import Foundation

enum UsagePeriod: String, CaseIterable, Identifiable {
    case today = "Today"
    var id: String { rawValue }
}

enum UsageMetric: String, CaseIterable, Identifiable {
    case tokens = "Tokens"
    case cost = "Estimated Cost"
    var id: String { rawValue }
    func formatted(_ value: Int) -> String {
        if value >= 1_000_000 { return String(format: "%.2fM", Double(value) / 1_000_000) }
        if value >= 1_000 { return String(format: "%.1fK", Double(value) / 1_000) }
        return value.formatted()
    }
}

struct CodexUsageProjection: Sendable {
    let inputTokens: Int
    let cachedInputTokens: Int
    let outputTokens: Int
    let cutoff: Date?
    let records: Int
    let coverage: CodexCoverage
    var totalTokens: Int { inputTokens + cachedInputTokens + outputTokens }
}

enum CodexCoverage: Sendable, Equatable {
    case importing
    case available
    case empty
    case accessError(String)
    var label: String {
        switch self {
        case .importing: "Importing local device activity"
        case .available: "Local device activity"
        case .empty: "No local activity found"
        case .accessError: "Local activity unavailable"
        }
    }
}
