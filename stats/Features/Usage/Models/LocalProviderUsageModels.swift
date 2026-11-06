import Foundation

/// Shared local-session providers that write into `local_usage_events`.
enum LocalProviderKind: String, Sendable, CaseIterable, Hashable {
    case claude
    case pi
    case grok
    case zai
    case antigravity

    var displayName: String {
        switch self {
        case .claude: "Claude"
        case .pi: "Pi"
        case .grok: "Grok"
        case .zai: "Z.ai"
        case .antigravity: "Antigravity"
        }
    }
}

struct LocalUsageEvent: Sendable, Equatable {
    let id: String
    let providerKind: LocalProviderKind
    let timestamp: Date
    let model: String?
    let underlyingProvider: String?
    let inputTokens: Int
    let cachedInputTokens: Int
    let cacheCreationTokens: Int
    let outputTokens: Int
    let reasoningTokens: Int

    var totalTokens: Int {
        inputTokens + cachedInputTokens + cacheCreationTokens + outputTokens + reasoningTokens
    }

    func pricingUsage() -> PricingTokenUsage {
        PricingTokenUsage(
            model: model,
            inputTokens: inputTokens,
            cacheReadTokens: cachedInputTokens + reasoningTokens,
            cacheWriteTokens: cacheCreationTokens,
            outputTokens: outputTokens
        )
    }
}

enum LocalUsageCoverage: Sendable, Equatable {
    case importing
    case available
    case empty
    case accessError(String)
    case unavailable(String)

    var label: String {
        switch self {
        case .importing: "Importing local activity"
        case .available: "Local activity"
        case .empty: "No local activity found"
        case .accessError: "Local activity unavailable"
        case .unavailable: "Local activity unavailable"
        }
    }
}

struct LocalUsageProjection: Sendable, Equatable {
    let inputTokens: Int
    let cachedInputTokens: Int
    let cacheCreationTokens: Int
    let outputTokens: Int
    let reasoningTokens: Int
    let cutoff: Date?
    let records: Int
    let coverage: LocalUsageCoverage

    var totalTokens: Int {
        inputTokens + cachedInputTokens + cacheCreationTokens + outputTokens + reasoningTokens
    }

    static func empty(coverage: LocalUsageCoverage = .empty) -> LocalUsageProjection {
        LocalUsageProjection(
            inputTokens: 0,
            cachedInputTokens: 0,
            cacheCreationTokens: 0,
            outputTokens: 0,
            reasoningTokens: 0,
            cutoff: nil,
            records: 0,
            coverage: coverage
        )
    }
}

enum LocalSourceOutcome: String, Sendable, Equatable {
    case imported
    case sourceMissing
    case readFailed
    case ledgerOnly
}

struct LocalSourceEvidence: Sendable, Equatable {
    let provider: LocalProviderKind
    let requestedWindowLabel: String
    let outcome: LocalSourceOutcome
    let eventCount: Int
    let tokenSubtotal: Int
    let earliestEvent: Date?
    let latestEvent: Date?
    let coverage: LocalUsageCoverage
    let safeErrorReason: String?
}

struct LocalEvidenceWindow: Sendable, Equatable, Identifiable {
    let label: String
    let requestedStart: Date
    let requestedEnd: Date
    let eventCount: Int
    let tokenSubtotal: Int
    let earliestEvent: Date?
    let latestEvent: Date?
    let underlyingProviders: [String]
    var id: String { label }
}

struct PiSourceEvidence: Sendable, Equatable {
    let generatedAt: Date
    let retentionDays: Int
    let windows: [LocalEvidenceWindow]
}
