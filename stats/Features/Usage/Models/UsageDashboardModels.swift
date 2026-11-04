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
        if value >= 1_000_000_000 { return String(format: "%.1fB", Double(value) / 1_000_000_000) }
        if value >= 1_000_000 { return String(format: "%.1fM", Double(value) / 1_000_000) }
        if value >= 1_000 { return String(format: "%.1fK", Double(value) / 1_000) }
        return value.formatted()
    }

    func formattedCost(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = Locale.current.currency?.identifier ?? "USD"
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: value)) ?? "—"
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

struct CursorUsageProjection: Sendable {
    let inputTokens: Int
    let cacheReadTokens: Int
    let cacheWriteTokens: Int
    let outputTokens: Int
    let cutoff: Date?
    let workspaceName: String?
    let coverage: CursorCoverage
    var totalTokens: Int { inputTokens + cacheReadTokens + cacheWriteTokens + outputTokens }
}

enum CursorCoverage: Sendable, Equatable {
    case disconnected
    case loading
    case available
    case unavailable(String)

    var label: String {
        switch self {
        case .disconnected: "Not connected"
        case .loading: "Refreshing account/workspace activity"
        case .available: "Account/workspace activity"
        case .unavailable: "Cursor activity unavailable"
        }
    }
}
