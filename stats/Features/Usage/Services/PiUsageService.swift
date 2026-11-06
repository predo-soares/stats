import Foundation

struct PiRefreshResult: Sendable {
    let projection: LocalUsageProjection
    let evidence: LocalSourceEvidence
    let underlyingProviders: [String]
}

struct PiUsageService: Sendable {
    let importer: PiUsageImporter
    private static let retentionDays = 90

    nonisolated init(importer: PiUsageImporter = PiUsageImporter()) {
        self.importer = importer
    }

    func refresh(
        into ledger: CodexUsageLedger,
        preserveOnFailure: Bool = true,
        now: Date = .now,
        calendar: Calendar = .current
    ) async throws -> PiRefreshResult {
        let todayRange = UsageDateRange(start: calendar.startOfDay(for: now), end: now)
        do {
            let events = try importer.importEvents()
            try await ledger.replaceLocal(provider: .pi, events: events)
            if let cutoff = calendar.date(byAdding: .day, value: -Self.retentionDays, to: now) {
                try await ledger.pruneLocalHistory(provider: .pi, before: cutoff)
            }
            let projection = try await ledger.localToday(provider: .pi, now: now, calendar: calendar)
            let underlying = try await ledger.localUnderlyingProviders(provider: .pi, range: todayRange)
            let evidence = try await ledger.localSourceEvidence(
                provider: .pi,
                requestedWindowLabel: "Today",
                range: todayRange,
                outcome: .imported,
                safeErrorReason: nil,
                now: now,
                calendar: calendar
            )
            return PiRefreshResult(projection: projection, evidence: evidence, underlyingProviders: underlying)
        } catch PiUsageImporter.PiImportError.sourceMissing {
            return try await retained(
                ledger: ledger,
                range: todayRange,
                coverage: .unavailable("Pi sessions were not found on this Mac."),
                outcome: .sourceMissing,
                safeErrorReason: "Local Pi sessions directory is missing.",
                preserveOnFailure: preserveOnFailure,
                now: now,
                calendar: calendar
            )
        } catch {
            return try await retained(
                ledger: ledger,
                range: todayRange,
                coverage: .accessError("Pi local activity could not be read."),
                outcome: .readFailed,
                safeErrorReason: "Pi session metadata could not be read.",
                preserveOnFailure: preserveOnFailure,
                now: now,
                calendar: calendar
            )
        }
    }

    private func retained(
        ledger: CodexUsageLedger,
        range: UsageDateRange,
        coverage: LocalUsageCoverage,
        outcome: LocalSourceOutcome,
        safeErrorReason: String,
        preserveOnFailure: Bool,
        now: Date,
        calendar: Calendar
    ) async throws -> PiRefreshResult {
        var projection = try await ledger.localToday(provider: .pi, now: now, calendar: calendar)
        if projection.records == 0 || !preserveOnFailure {
            projection = .empty(coverage: coverage)
        } else {
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
        }
        let underlying = try await ledger.localUnderlyingProviders(provider: .pi, range: range)
        let evidence = try await ledger.localSourceEvidence(
            provider: .pi,
            requestedWindowLabel: "Today",
            range: range,
            outcome: outcome,
            safeErrorReason: safeErrorReason,
            now: now,
            calendar: calendar
        )
        return PiRefreshResult(projection: projection, evidence: evidence, underlyingProviders: underlying)
    }
}
