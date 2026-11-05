import Foundation

struct CursorUsageService: Sendable {
    let client: CursorUsageClient
    let quotaClient: CursorQuotaClient
    let vault: CursorCredentialVault
    let authentication: CursorBrowserAuthentication
    let workspaceScopes: any CursorWorkspaceScopeSource
    let tokenRenewal: CursorTokenRenewal

    init(
        client: CursorUsageClient = CursorUsageClient(),
        quotaClient: CursorQuotaClient = CursorQuotaClient(),
        vault: CursorCredentialVault = CursorCredentialVault(),
        authentication: CursorBrowserAuthentication = CursorBrowserAuthentication(),
        workspaceScopes: any CursorWorkspaceScopeSource = AccountDefaultCursorWorkspaceScopeSource(),
        tokenRenewal: CursorTokenRenewal = CursorTokenRenewal()
    ) {
        self.client = client
        self.quotaClient = quotaClient
        self.vault = vault
        self.authentication = authentication
        self.workspaceScopes = workspaceScopes
        self.tokenRenewal = tokenRenewal
    }

    func loadCredential() throws -> CursorCredential? {
        try vault.load()
    }

    func hasCredential() -> Bool {
        (try? vault.load()) != nil
    }

    func beginAuthorization() throws -> CursorBrowserAuthorization {
        try authentication.begin()
    }

    func awaitAuthorization(_ authorization: CursorBrowserAuthorization) async throws -> CursorAuthenticatedSession {
        try await authentication.awaitCompletion(for: authorization)
    }

    func availableWorkspaceScopes(for session: CursorAuthenticatedSession) async throws -> [CursorWorkspaceScope] {
        try await workspaceScopes.availableScopes(for: session)
    }

    func connect(session: CursorAuthenticatedSession, preferredWorkspaceID: String? = nil) async throws -> CursorCredential {
        let scopes = try await availableWorkspaceScopes(for: session)
        let selection = try CursorWorkspaceSelection.resolve(scopes: scopes, preferredID: preferredWorkspaceID)
        let expiresAt = tokenRenewal.jwtExpiry(session.accessToken)
        let credential = session.credential(
            workspaceID: selection.scope.id,
            workspaceName: selection.scope.name,
            expiresAt: expiresAt
        )
        try vault.save(credential)
        return credential
    }

    func disconnect() throws {
        try vault.clear()
    }

    func refresh(
        into ledger: CodexUsageLedger,
        onProgress: @Sendable @escaping (CursorUsageProjection) async -> Void = { _ in }
    ) async throws -> (projection: CursorUsageProjection, quota: CursorQuotaPublication) {
        guard var credential = try vault.load() else {
            throw CursorUsageClientError.invalidSession
        }
        if tokenRenewal.needsRenewal(credential) {
            do {
                credential = try await tokenRenewal.renew(credential)
                try vault.save(credential)
            } catch {
                if credential.expiresAt.map({ $0 <= Date.now }) == true {
                    throw CursorUsageClientError.invalidSession
                }
            }
        }
        do {
            return try await fetch(credential: credential, into: ledger, onProgress: onProgress)
        } catch CursorUsageClientError.invalidSession {
            credential = try await tokenRenewal.renew(credential)
            try vault.save(credential)
            return try await fetch(credential: credential, into: ledger, onProgress: onProgress)
        }
    }

    private func fetch(
        credential: CursorCredential,
        into ledger: CodexUsageLedger,
        onProgress: @Sendable @escaping (CursorUsageProjection) async -> Void
    ) async throws -> (projection: CursorUsageProjection, quota: CursorQuotaPublication) {
        let sessionCookie = credential.sessionCookie
        let quota = await quotaClient.refresh(sessionToken: sessionCookie)
        let now = Date.now
        let calendar = Calendar.current
        let current = UsageComparisonPeriod.last30Days.currentInterval(now: now, calendar: calendar)
        let baseline = UsageComparisonPeriod.last30Days.baselineInterval(now: now, calendar: calendar)
        let retentionBoundary = calendar.date(byAdding: .day, value: -90, to: calendar.startOfDay(for: now)) ?? now
        try await ledger.pruneCursorHistory(workspaceID: credential.workspaceID, before: retentionBoundary)
        let ranges = [
            CursorUsageRange(start: current.start, end: current.end),
            CursorUsageRange(start: baseline.start, end: baseline.end),
        ]
        try await ledger.seedCursorImportRanges(ranges, workspaceID: credential.workspaceID, now: now)
        try await importAvailableRanges(sessionToken: sessionCookie, workspaceID: credential.workspaceID, workspaceName: credential.workspaceName, ledger: ledger, now: now, onProgress: onProgress)

        let todayRange = UsageDateRange(start: calendar.startOfDay(for: now), end: now)
        let todayCoverage = try await ledger.cursorCoverage(workspaceID: credential.workspaceID, range: todayRange)
        let cached = try await ledger.cursorToday(
            workspaceID: credential.workspaceID,
            workspaceName: credential.workspaceName,
            now: now,
            calendar: calendar
        )
        let coverage: CursorCoverage
        switch todayCoverage {
        case .complete: coverage = cached.cutoff == nil ? .empty : .available
        case .incomplete: coverage = cached.cutoff == nil ? .loading : .incomplete("Cursor history is still importing.")
        }
        return (CursorUsageProjection(
            inputTokens: cached.inputTokens, cacheReadTokens: cached.cacheReadTokens,
            cacheWriteTokens: cached.cacheWriteTokens, outputTokens: cached.outputTokens,
            cutoff: cached.cutoff, workspaceName: cached.workspaceName, coverage: coverage
        ), quota)
    }

    /// Imports a bounded number of durable work items. Every completed page range is committed
    /// before another network request starts, so relaunches resume from the ledger rather than
    /// reconstructing a daily request burst.
    private func importAvailableRanges(
        sessionToken: String,
        workspaceID: String,
        workspaceName: String,
        ledger: CodexUsageLedger,
        now: Date,
        onProgress: @Sendable @escaping (CursorUsageProjection) async -> Void
    ) async throws {
        for _ in 0..<8 {
            try Task.checkCancellation()
            guard let checkpoint = try await ledger.nextCursorImportRange(workspaceID: workspaceID, now: now) else { return }
            do {
                let outcome = try await client.fetchRange(sessionToken: sessionToken, range: checkpoint.range)
                try await ledger.completeCursorImport(outcome, workspaceID: workspaceID, range: checkpoint.range, now: now)
                let cached = try await ledger.cursorToday(workspaceID: workspaceID, workspaceName: workspaceName, now: now)
                await onProgress(CursorUsageProjection(
                    inputTokens: cached.inputTokens, cacheReadTokens: cached.cacheReadTokens,
                    cacheWriteTokens: cached.cacheWriteTokens, outputTokens: cached.outputTokens,
                    cutoff: cached.cutoff, workspaceName: workspaceName, coverage: .loading
                ))
            } catch is CancellationError {
                throw CancellationError()
            } catch CursorUsageClientError.invalidSession {
                throw CursorUsageClientError.invalidSession
            } catch CursorUsageClientError.rateLimited(let retryAfter) {
                try await ledger.deferCursorImport(checkpoint.range, workspaceID: workspaceID, retryAfter: retryAfter ?? now.addingTimeInterval(300), message: "Cursor requested a later retry.", now: now)
                return
            } catch {
                if let halves = checkpoint.range.split() {
                    try await ledger.splitCursorImport(checkpoint.range, workspaceID: workspaceID, into: [halves.0, halves.1], now: now)
                } else {
                    let message = (error as? LocalizedError)?.errorDescription ?? "Cursor history could not be imported."
                    try await ledger.deferCursorImport(checkpoint.range, workspaceID: workspaceID, retryAfter: now.addingTimeInterval(300), message: message, now: now)
                }
            }
        }
    }
}
