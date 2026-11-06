import Foundation

struct ClaudeRefreshResult: Sendable {
    let projection: LocalUsageProjection
    let evidence: LocalSourceEvidence
}

struct ClaudeUsageService: Sendable {
    let importer: ClaudeUsageImporter

    nonisolated init(importer: ClaudeUsageImporter = ClaudeUsageImporter()) {
        self.importer = importer
    }

    func refresh(
        into ledger: CodexUsageLedger,
        preserveOnFailure: Bool = true,
        now: Date = .now,
        calendar: Calendar = .current
    ) async throws -> ClaudeRefreshResult {
        let todayRange = UsageDateRange(start: calendar.startOfDay(for: now), end: now)
        if !importer.isSourceAvailable {
            return try await retainedResult(
                ledger: ledger,
                range: todayRange,
                coverage: .unavailable("Claude project transcripts were not found on this Mac."),
                outcome: .sourceMissing,
                safeErrorReason: "Local Claude projects directory is missing.",
                preserveOnFailure: preserveOnFailure,
                now: now,
                calendar: calendar
            )
        }
        do {
            let projection = try await importer.importAvailableSessions(into: ledger, now: now)
            let evidence = try await ledger.localSourceEvidence(
                provider: .claude,
                requestedWindowLabel: "Today",
                range: todayRange,
                outcome: .imported,
                safeErrorReason: nil,
                now: now,
                calendar: calendar
            )
            return ClaudeRefreshResult(projection: projection, evidence: evidence)
        } catch {
            return try await retainedResult(
                ledger: ledger,
                range: todayRange,
                coverage: .accessError("Claude local activity could not be read."),
                outcome: .readFailed,
                safeErrorReason: "Claude transcripts could not be read.",
                preserveOnFailure: preserveOnFailure,
                now: now,
                calendar: calendar
            )
        }
    }

    private func retainedResult(
        ledger: CodexUsageLedger,
        range: UsageDateRange,
        coverage: LocalUsageCoverage,
        outcome: LocalSourceOutcome,
        safeErrorReason: String,
        preserveOnFailure: Bool,
        now: Date,
        calendar: Calendar
    ) async throws -> ClaudeRefreshResult {
        var projection = try await ledger.localToday(provider: .claude, now: now, calendar: calendar)
        if projection.records == 0, !preserveOnFailure {
            projection = .empty(coverage: coverage)
        } else if projection.records > 0 {
            projection = LocalUsageProjection(
                inputTokens: projection.inputTokens,
                cachedInputTokens: projection.cachedInputTokens,
                cacheCreationTokens: projection.cacheCreationTokens,
                outputTokens: projection.outputTokens,
                reasoningTokens: projection.reasoningTokens,
                cutoff: projection.cutoff,
                records: projection.records,
                coverage: coverage
            )
        } else {
            projection = .empty(coverage: coverage)
        }
        let evidence = try await ledger.localSourceEvidence(
            provider: .claude,
            requestedWindowLabel: "Today",
            range: range,
            outcome: outcome,
            safeErrorReason: safeErrorReason,
            now: now,
            calendar: calendar
        )
        return ClaudeRefreshResult(projection: projection, evidence: evidence)
    }
}
