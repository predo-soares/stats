import Foundation
import Observation

@MainActor @Observable final class UsageStore {
    var codex: CodexUsageProjection
    var isImporting = false
    private let ledger: CodexUsageLedger?
    private let importer = CodexUsageImporter()

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
}
