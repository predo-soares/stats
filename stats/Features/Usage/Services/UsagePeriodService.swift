import Foundation

struct UsagePeriodSnapshot: Sendable {
    let codexForPeriod: CodexUsageProjection
    let cursorForPeriod: CursorUsageProjection?
    let claudeForPeriod: LocalUsageProjection?
    let codexComparison: UsageTokenComparison
    let cursorComparison: UsageTokenComparison
    let claudeComparison: UsageTokenComparison?
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
    let claudeModelTotals: [UsageModelTotal]
    let claudeTrend: [UsageTrendBucket]
    let piModelTotals: [UsageModelTotal]
    let piTrend: [UsageTrendBucket]
}

struct UsagePeriodService: Sendable {
    let pricingCatalog: PricingCatalog

    func loadPeriod(
        ledger: CodexUsageLedger,
        period: UsageComparisonPeriod,
        credential: CursorCredential?,
        includeClaude: Bool = false,
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
        let claudeForPeriod: LocalUsageProjection?
        let claudeComparison: UsageTokenComparison?
        if includeClaude {
            let currentClaude = try await ledger.local(provider: .claude, range: currentRange)
            let baselineClaude = try await ledger.local(provider: .claude, range: baselineRange)
            claudeForPeriod = currentClaude
            claudeComparison = .make(
                current: currentClaude.totalTokens,
                baseline: baselineClaude.records == 0 ? nil : baselineClaude.totalTokens,
                coverage: baselineClaude.records == 0 ? .incomplete("Previous Claude history is unavailable.") : .complete
            )
        } else {
            claudeForPeriod = nil
            claudeComparison = nil
        }

        guard let credential else {
            let combinedCurrent = currentCodex.totalTokens + (claudeForPeriod?.totalTokens ?? 0)
            return UsagePeriodSnapshot(
                codexForPeriod: currentCodex,
                cursorForPeriod: nil,
                claudeForPeriod: claudeForPeriod,
                codexComparison: codexComparison,
                cursorComparison: .make(current: 0, baseline: nil, coverage: .unavailable("Cursor history is unavailable.")),
                claudeComparison: claudeComparison,
                combinedComparison: .make(current: combinedCurrent, baseline: nil, coverage: .unavailable("Combined comparison is unavailable until both providers have history.")),
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

        let cursorProjection = try await ledger.cursor(
            workspaceID: credential.workspaceID,
            workspaceName: credential.workspaceName,
            range: currentRange
        )
        let baselineCursor = try await ledger.cursor(
            workspaceID: credential.workspaceID,
            workspaceName: credential.workspaceName,
            range: baselineRange
        )
        let currentCursorCoverage = try await ledger.cursorCoverage(workspaceID: credential.workspaceID, range: currentRange)
        let baselineCursorCoverage = try await ledger.cursorCoverage(workspaceID: credential.workspaceID, range: baselineRange)
        let currentCursor: CursorUsageProjection
        switch currentCursorCoverage {
        case .complete:
            currentCursor = cursorProjection
        case .incomplete:
            currentCursor = CursorUsageProjection(
                inputTokens: cursorProjection.inputTokens, cacheReadTokens: cursorProjection.cacheReadTokens,
                cacheWriteTokens: cursorProjection.cacheWriteTokens, outputTokens: cursorProjection.outputTokens,
                cutoff: cursorProjection.cutoff, workspaceName: cursorProjection.workspaceName,
                coverage: .incomplete("Cursor history is incomplete for this period.")
            )
        }
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
        let cursorHistoryComplete: Bool
        switch (currentCursorCoverage, baselineCursorCoverage) {
        case (.complete, .complete): cursorHistoryComplete = true
        default: cursorHistoryComplete = false
        }
        let costCoverage: UsageComparisonCoverage = cursorHistoryComplete && baselineCodexCost.isComplete && baselineCursorCost.isComplete
            ? .complete
            : .incomplete(cursorHistoryComplete ? "Cost comparison is incomplete because one or more models are unpriced." : "Cursor history is incomplete for this comparison.")
        let claudeTokens = claudeForPeriod?.totalTokens ?? 0
        let combinedComparison: UsageTokenComparison
        if baselineCodex.records > 0, cursorHistoryComplete {
            combinedComparison = .make(
                current: currentCodex.totalTokens + currentCursor.totalTokens + claudeTokens,
                baseline: baselineCodex.totalTokens + baselineCursor.totalTokens + (claudeComparison?.baseline ?? 0),
                coverage: .complete
            )
        } else {
            combinedComparison = .make(
                current: currentCodex.totalTokens + currentCursor.totalTokens + claudeTokens,
                baseline: nil,
                coverage: .unavailable("Combined comparison is unavailable until both providers have history.")
            )
        }

        return UsagePeriodSnapshot(
            codexForPeriod: currentCodex,
            cursorForPeriod: currentCursor,
            claudeForPeriod: claudeForPeriod,
            codexComparison: codexComparison,
            cursorComparison: .make(
                current: currentCursor.totalTokens,
                baseline: cursorHistoryComplete ? baselineCursor.totalTokens : nil,
                coverage: cursorHistoryComplete ? .complete : .incomplete("Cursor history is incomplete for this comparison.")
            ),
            claudeComparison: claudeComparison,
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
        includeClaude: Bool = false,
        includePi: Bool = false,
        now: Date = .now,
        calendar: Calendar = .current
    ) async throws -> UsageProviderDetailsSnapshot {
        let range = UsageDateRange(start: calendar.startOfDay(for: now), end: now)
        let codexModelTotals = try await ledger.modelTotals(range: range)
        let codexTrend = try await ledger.trend(range: range, granularity: .hourly)
        let claudeModelTotals = includeClaude
            ? try await ledger.localModelTotals(provider: .claude, range: range)
            : []
        let claudeTrend = includeClaude
            ? try await ledger.localTrend(provider: .claude, range: range, granularity: .hourly, calendar: calendar)
            : []
        let piModelTotals = includePi
            ? try await ledger.localModelTotals(provider: .pi, range: range)
            : []
        let piTrend = includePi
            ? try await ledger.localTrend(provider: .pi, range: range, granularity: .hourly, calendar: calendar)
            : []
        guard let credential else {
            return UsageProviderDetailsSnapshot(
                codexModelTotals: codexModelTotals,
                codexTrend: codexTrend,
                cursorModelTotals: [],
                cursorTrend: [],
                claudeModelTotals: claudeModelTotals,
                claudeTrend: claudeTrend,
                piModelTotals: piModelTotals,
                piTrend: piTrend
            )
        }
        return UsageProviderDetailsSnapshot(
            codexModelTotals: codexModelTotals,
            codexTrend: codexTrend,
            cursorModelTotals: try await ledger.modelTotals(range: range, workspaceID: credential.workspaceID),
            cursorTrend: try await ledger.trend(range: range, granularity: .hourly, workspaceID: credential.workspaceID),
            claudeModelTotals: claudeModelTotals,
            claudeTrend: claudeTrend,
            piModelTotals: piModelTotals,
            piTrend: piTrend
        )
    }

    func estimateLocalCost(
        ledger: CodexUsageLedger,
        provider: LocalProviderKind,
        now: Date = .now,
        calendar: Calendar = .current
    ) async throws -> UsageCostResult {
        let range = UsageDateRange(start: calendar.startOfDay(for: now), end: now)
        let usage = try await ledger.localPricingUsage(provider: provider, range: range)
        return UsageCosting(catalog: pricingCatalog).estimate(usage)
    }
}
