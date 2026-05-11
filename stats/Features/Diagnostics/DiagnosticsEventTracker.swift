import Foundation

struct DiagnosticsTrackedState {
    var activeIssues: [DiagnosticsIssueEvent]
    var recentResolvedIssues: [DiagnosticsIssueEvent]
    var didChange: Bool
}

struct DiagnosticsEventTracker {
    private(set) var activeIssuesByType: [DiagnosticsIssueType: DiagnosticsIssueEvent] = [:]
    private(set) var resolvedIssueHistory: [DiagnosticsIssueEvent] = []

    mutating func restore(active: [DiagnosticsIssueEvent], resolved: [DiagnosticsIssueEvent]) {
        activeIssuesByType = Dictionary(uniqueKeysWithValues: active.map { ($0.type, $0) })
        resolvedIssueHistory = resolved.sorted { lhs, rhs in
            let lhsDate = lhs.resolvedAt ?? lhs.lastSeenAt
            let rhsDate = rhs.resolvedAt ?? rhs.lastSeenAt
            return lhsDate > rhsDate
        }
    }

    mutating func apply(drafts: [DiagnosticsIssueDraft], at timestamp: Date) -> DiagnosticsTrackedState {
        let oldActive = activeIssuesByType
        var nextActive: [DiagnosticsIssueType: DiagnosticsIssueEvent] = [:]
        var didChange = false

        for draft in drafts {
            if var existing = oldActive[draft.type] {
                existing.status = .active
                existing.severity = draft.severity
                existing.title = draft.title
                existing.suggestedAction = draft.suggestedAction
                existing.contributingRuleIDs = draft.contributingRuleIDs
                existing.context = draft.context
                existing.lastSeenAt = timestamp
                nextActive[draft.type] = existing
                if existing != oldActive[draft.type] {
                    didChange = true
                }
            } else {
                nextActive[draft.type] = DiagnosticsIssueEvent(
                    id: UUID().uuidString,
                    type: draft.type,
                    status: .active,
                    severity: draft.severity,
                    title: draft.title,
                    suggestedAction: draft.suggestedAction,
                    contributingRuleIDs: draft.contributingRuleIDs,
                    openedAt: timestamp,
                    lastSeenAt: timestamp,
                    resolvedAt: nil,
                    context: draft.context
                )
                didChange = true
            }
        }

        for (type, existing) in oldActive where nextActive[type] == nil {
            var resolved = existing
            resolved.status = .resolved
            resolved.lastSeenAt = timestamp
            resolved.resolvedAt = timestamp
            resolvedIssueHistory.insert(resolved, at: 0)
            if resolvedIssueHistory.count > 100 {
                resolvedIssueHistory = Array(resolvedIssueHistory.prefix(100))
            }
            didChange = true
        }

        activeIssuesByType = nextActive

        return DiagnosticsTrackedState(
            activeIssues: nextActive.values.sorted(by: Self.sort),
            recentResolvedIssues: Array(resolvedIssueHistory.prefix(5)),
            didChange: didChange
        )
    }

    mutating func clearResolvedHistory() {
        resolvedIssueHistory = []
    }

    nonisolated static func sort(lhs: DiagnosticsIssueEvent, rhs: DiagnosticsIssueEvent) -> Bool {
        if lhs.severity.sortPriority != rhs.severity.sortPriority {
            return lhs.severity.sortPriority > rhs.severity.sortPriority
        }

        if lhs.isActionable != rhs.isActionable {
            return lhs.isActionable
        }

        return lhs.lastSeenAt > rhs.lastSeenAt
    }
}
