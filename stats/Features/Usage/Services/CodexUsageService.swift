import Foundation

struct CodexUsageService: Sendable {
    let importer: CodexUsageImporter
    let quotaClient: CodexQuotaClient

    func importToday(into ledger: CodexUsageLedger) async throws -> CodexUsageProjection {
        try await importer.importAvailableSessions(into: ledger)
    }

    func refreshQuota(confirmedIdentity: String?, retained: CodexQuotaSnapshot?) async -> CodexQuotaPublication {
        await quotaClient.refresh(confirmedIdentity: confirmedIdentity, retained: retained)
    }
}
