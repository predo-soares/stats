import Foundation
import Observation

@MainActor @Observable final class UsageStore {
    var codex: CodexUsageProjection
    var cursor = CursorUsageProjection(inputTokens: 0, cacheReadTokens: 0, cacheWriteTokens: 0, outputTokens: 0, cutoff: nil, workspaceName: nil, coverage: .disconnected)
    var codexQuota: CodexQuotaPublication = .authenticationMissing
    var isImporting = false
    private let ledger: CodexUsageLedger?
    private let importer = CodexUsageImporter()
    private let cursorClient = CursorUsageClient()
    private let cursorVault = CursorCredentialVault()
    private let quotaClient = CodexQuotaClient(credentialReader: UnavailableCodexCredentialReader(), transport: UnavailableCodexQuotaTransport())

    init() {
        do { let ledger = try CodexUsageLedger(); self.ledger = ledger; self.codex = (try? ledger.today(now: .now)) ?? CodexUsageProjection(inputTokens: 0, cachedInputTokens: 0, outputTokens: 0, cutoff: nil, records: 0, coverage: .empty) }
        catch { self.ledger = nil; self.codex = CodexUsageProjection(inputTokens: 0, cachedInputTokens: 0, outputTokens: 0, cutoff: nil, records: 0, coverage: .accessError("The local usage ledger could not open.")) }
    }

    func refreshCodex() {
        guard !isImporting, let ledger else { return }
        isImporting = true
        let importer = self.importer
        Task {
            do { codex = try await Task.detached { try importer.importAvailableSessions(into: ledger) }.value }
            catch { codex = CodexUsageProjection(inputTokens: codex.inputTokens, cachedInputTokens: codex.cachedInputTokens, outputTokens: codex.outputTokens, cutoff: codex.cutoff, records: codex.records, coverage: .accessError("Local activity could not be imported.")) }
            isImporting = false
        }
    }

    func refreshCursor() {
        guard let ledger else { return }
        do {
            guard let credential = try cursorVault.load() else { cursor = CursorUsageProjection(inputTokens: 0, cacheReadTokens: 0, cacheWriteTokens: 0, outputTokens: 0, cutoff: nil, workspaceName: nil, coverage: .disconnected); return }
            cursor = CursorUsageProjection(inputTokens: cursor.inputTokens, cacheReadTokens: cursor.cacheReadTokens, cacheWriteTokens: cursor.cacheWriteTokens, outputTokens: cursor.outputTokens, cutoff: cursor.cutoff, workspaceName: credential.workspaceName, coverage: .loading)
            let client = cursorClient
            Task {
                do {
                    let events = try await client.fetchToday(sessionToken: credential.sessionToken)
                    try await Task.detached { try ledger.upsertCursor(events, workspaceID: credential.workspaceID) }.value
                    cursor = try await Task.detached { try ledger.cursorToday(workspaceID: credential.workspaceID, workspaceName: credential.workspaceName, now: .now) }.value
                } catch { cursor = CursorUsageProjection(inputTokens: 0, cacheReadTokens: 0, cacheWriteTokens: 0, outputTokens: 0, cutoff: nil, workspaceName: credential.workspaceName, coverage: .unavailable("Cursor could not refresh its selected workspace.")) }
            }
        } catch { cursor = CursorUsageProjection(inputTokens: 0, cacheReadTokens: 0, cacheWriteTokens: 0, outputTokens: 0, cutoff: nil, workspaceName: nil, coverage: .unavailable("Cursor credentials are unavailable in Keychain.")) }
    }

    func refreshCodexQuota() {
        let client = quotaClient
        let retained: CodexQuotaSnapshot?
        let identity: String?
        if case let .published(snapshot) = codexQuota { retained = snapshot; identity = snapshot.accountIdentity }
        else { retained = nil; identity = nil }
        Task { codexQuota = await client.refresh(confirmedIdentity: identity, retained: retained) }
    }
}
