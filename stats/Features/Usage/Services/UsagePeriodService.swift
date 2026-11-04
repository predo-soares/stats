import Foundation

struct UsagePeriodSnapshot: Sendable {
    let codexForPeriod: CodexUsageProjection
    let cursorForPeriod: CursorUsageProjection?
    let codexComparison: UsageTokenComparison
    let cursorComparison: UsageTokenComparison
    let combinedComparison: UsageTokenComparison
    let codexCost: UsageCostResult
    let cursorCost: UsageCostResult?
    let combinedCost: UsageCostResult
    let combinedCostComparison: UsageCostComparison
}

struct UsageProviderDetailsSnapshot: Sendable {
    let codexModelTotals: [UsageModelTotal]
    let codexTrend: [UsageTrendBucket]
    let cursorModelTotals: [UsageModelTotal]
    let cursorTrend: [UsageTrendBucket]
}

struct UsagePeriodService: Sendable {
    let pricingCatalog: PricingCatalog

    func loadPeriod(
        ledger: CodexUsageLedger,
        period: UsageComparisonPeriod,
        credential: CursorCredential?,
        now: Date = .now,
        calendar: Calendar = .current
    ) async throws -> UsagePeriodSnapshot {
        let current = period.currentInterval(now: now, calendar: calendar)
        let baseline = period.baselineInterval(now: now, calendar: calendar)
        let currentRange = UsageDateRange(start: current.start, end: current.end)
        let baselineRange = UsageDateRange(start: baseline.start, end: baseline.end)
        let costing = UsageCosting(catalog: pricingCatalog)

        let currentCodex = try await ledger.codex(range: currentRange)
        let baselineCodex = try await ledger.codex(range: baselineRange)
        let currentCodexCost = costing.estimate(try await ledger.pricingUsage(range: currentRange))
        let baselineCodexCost = costing.estimate(try await ledger.pricingUsage(range: baselineRange))
        let codexComparison = UsageTokenComparison.make(
            current: currentCodex.totalTokens,
            baseline: baselineCodex.records == 0 ? nil : baselineCodex.totalTokens,
            coverage: baselineCodex.records == 0 ? .incomplete("Previous Codex history is unavailable.") : .complete
        )

        guard let credential else {
            return UsagePeriodSnapshot(
                codexForPeriod: currentCodex,
                cursorForPeriod: nil,
                codexComparison: codexComparison,
                cursorComparison: .make(current: 0, baseline: nil, coverage: .unavailable("Cursor history is unavailable.")),
                combinedComparison: .make(current: currentCodex.totalTokens, baseline: nil, coverage: .unavailable("Combined comparison is unavailable until both providers have history.")),
                codexCost: currentCodexCost,
                cursorCost: nil,
                combinedCost: currentCodexCost,
                combinedCostComparison: UsageCostComparison.make(
                    current: currentCodexCost.estimate,
                    baseline: baselineCodexCost.estimate,
                    coverage: .unavailable("Combined cost comparison is unavailable until Cursor history is available.")
                )
            )
        }

        let currentCursor = try await ledger.cursor(
            workspaceID: credential.workspaceID,
            workspaceName: credential.workspaceName,
            range: currentRange
        )
        let baselineCursor = try await ledger.cursor(
            workspaceID: credential.workspaceID,
            workspaceName: credential.workspaceName,
            range: baselineRange
        )
        let currentCursorCost = costing.estimate(try await ledger.pricingUsage(range: currentRange, workspaceID: credential.workspaceID))
        let baselineCursorCost = costing.estimate(try await ledger.pricingUsage(range: baselineRange, workspaceID: credential.workspaceID))
        let combinedCost = UsageCostResult(
            estimate: currentCodexCost.estimate + currentCursorCost.estimate,
            catalogRevision: pricingCatalog.revision,
            usageRecords: currentCodexCost.usageRecords + currentCursorCost.usageRecords
        )
        let baselineCombined = UsageCostResult(
            estimate: baselineCodexCost.estimate + baselineCursorCost.estimate,
            catalogRevision: pricingCatalog.revision,
            usageRecords: baselineCodexCost.usageRecords + baselineCursorCost.usageRecords
        )
        let costCoverage: UsageComparisonCoverage = baselineCodexCost.isComplete && baselineCursorCost.isComplete
            ? .complete
            : .incomplete("Cost comparison is incomplete because one or more models are unpriced.")
        let combinedComparison: UsageTokenComparison
        if baselineCodex.records > 0, baselineCursor.cutoff != nil {
            combinedComparison = .make(
                current: currentCodex.totalTokens + currentCursor.totalTokens,
                baseline: baselineCodex.totalTokens + baselineCursor.totalTokens,
                coverage: .complete
            )
        } else {
            combinedComparison = .make(
                current: currentCodex.totalTokens + currentCursor.totalTokens,
                baseline: nil,
                coverage: .unavailable("Combined comparison is unavailable until both providers have history.")
            )
        }

        return UsagePeriodSnapshot(
            codexForPeriod: currentCodex,
            cursorForPeriod: currentCursor,
            codexComparison: codexComparison,
            cursorComparison: .make(
                current: currentCursor.totalTokens,
                baseline: baselineCursor.cutoff == nil ? nil : baselineCursor.totalTokens,
                coverage: baselineCursor.cutoff == nil ? .incomplete("Previous Cursor history is unavailable.") : .complete
            ),
            combinedComparison: combinedComparison,
            codexCost: currentCodexCost,
            cursorCost: currentCursorCost,
            combinedCost: combinedCost,
            combinedCostComparison: UsageCostComparison.make(
                current: combinedCost.estimate,
                baseline: baselineCombined.estimate,
                coverage: costCoverage
            )
        )
    }

    func loadProviderDetails(
        ledger: CodexUsageLedger,
        credential: CursorCredential?,
        now: Date = .now,
        calendar: Calendar = .current
    ) async throws -> UsageProviderDetailsSnapshot {
        let range = UsageDateRange(start: calendar.startOfDay(for: now), end: now)
        let codexModelTotals = try await ledger.modelTotals(range: range)
        let codexTrend = try await ledger.trend(range: range, granularity: .hourly)
        guard let credential else {
            return UsageProviderDetailsSnapshot(
                codexModelTotals: codexModelTotals,
                codexTrend: codexTrend,
                cursorModelTotals: [],
                cursorTrend: []
            )
        }
        return UsageProviderDetailsSnapshot(
            codexModelTotals: codexModelTotals,
            codexTrend: codexTrend,
            cursorModelTotals: try await ledger.modelTotals(range: range, workspaceID: credential.workspaceID),
            cursorTrend: try await ledger.trend(range: range, granularity: .hourly, workspaceID: credential.workspaceID)
        )
    }
}
