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

    func refresh(into ledger: CodexUsageLedger) async throws -> (projection: CursorUsageProjection, quota: CursorQuotaPublication) {
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
            return try await fetch(credential: credential, into: ledger)
        } catch CursorUsageClientError.invalidSession {
            credential = try await tokenRenewal.renew(credential)
            try vault.save(credential)
            return try await fetch(credential: credential, into: ledger)
        }
    }

    private func fetch(
        credential: CursorCredential,
        into ledger: CodexUsageLedger
    ) async throws -> (projection: CursorUsageProjection, quota: CursorQuotaPublication) {
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
