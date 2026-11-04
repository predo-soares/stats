import Foundation

struct CursorUsageService: Sendable {
    let client: CursorUsageClient
    let quotaClient: CursorQuotaClient
    let vault: CursorCredentialVault
    let authentication: CursorBrowserAuthentication

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

    func saveDefaultWorkspace(_ session: CursorAuthenticatedSession) throws {
        // Cursor's observed usage endpoint is scoped by the authenticated account, not a
        // workspace parameter. Keep a stable local scope key so a later reconnected account
        // cannot be merged with the current ledger, while presenting it as the default scope.
        let scopeID = "default:\(session.accountID)"
        try vault.save(session.credential(workspaceID: scopeID, workspaceName: "Default workspace"))
    }

    func disconnect() throws {
        try vault.clear()
    }

    func refresh(into ledger: CodexUsageLedger) async throws -> (projection: CursorUsageProjection, quota: CursorQuotaPublication) {
        guard let credential = try vault.load() else {
            throw CursorUsageClientError.invalidSession
        }
        let quota = await quotaClient.refresh(sessionToken: credential.sessionToken)
        let events = try await client.fetchHistory(sessionToken: credential.sessionToken, days: 60)
        try await ledger.upsertCursor(events, workspaceID: credential.workspaceID)
        let projection = try await ledger.cursorToday(
            workspaceID: credential.workspaceID,
            workspaceName: credential.workspaceName,
            now: .now
        )
        return (projection, quota)
    }
}
