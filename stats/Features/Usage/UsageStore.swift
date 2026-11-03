import AppKit
import Foundation
import Observation

@MainActor @Observable final class UsageStore {
    var codex: CodexUsageProjection
    var cursor = CursorUsageProjection(inputTokens: 0, cacheReadTokens: 0, cacheWriteTokens: 0, outputTokens: 0, cutoff: nil, workspaceName: nil, coverage: .disconnected)
    var codexQuota: CodexQuotaPublication = .authenticationMissing
    var cursorQuota: CursorQuotaPublication = .unavailable("Cursor quota is not connected.")
    var cursorConnectionMessage: String?
    var isConnectingCursor = false
    var isImporting = false
    var selectedPeriod: UsageComparisonPeriod = .today
    var codexForPeriod: CodexUsageProjection?
    var cursorForPeriod: CursorUsageProjection?
    var codexComparison = UsageTokenComparison.make(current: 0, baseline: nil, coverage: .unavailable("Comparison is not ready."))
    var cursorComparison = UsageTokenComparison.make(current: 0, baseline: nil, coverage: .unavailable("Comparison is not ready."))
    var combinedComparison = UsageTokenComparison.make(current: 0, baseline: nil, coverage: .unavailable("Comparison is not ready."))
    var codexCost: UsageCostResult?
    var cursorCost: UsageCostResult?
    var combinedCost: UsageCostResult?
    var combinedCostComparison = UsageCostComparison.make(current: CostEstimate(pricedCost: 0, pricedTokens: 0, unpricedTokens: 0, unpricedModels: []), baseline: nil, coverage: .unavailable("Cost comparison is not ready."))
    var codexModelTotals: [UsageModelTotal] = []
    var cursorModelTotals: [UsageModelTotal] = []
    var codexTrend: [UsageTrendBucket] = []
    var cursorTrend: [UsageTrendBucket] = []
    private(set) var codexRefresh = ProviderRefreshSnapshot<CodexUsageProjection>(value: nil, state: .disconnected)
    private(set) var cursorRefresh = ProviderRefreshSnapshot<CursorUsageProjection>(value: nil, state: .disconnected)
    private let ledger: CodexUsageLedger?
    private let importer = CodexUsageImporter()
    private let cursorClient = CursorUsageClient()
    private let cursorQuotaClient = CursorQuotaClient()
    private let cursorVault = CursorCredentialVault()
    private let cursorAuthentication = CursorBrowserAuthentication()
    private var didAttemptAutomaticCursorConnection = false
    private let quotaClient = CodexQuotaClient(credentialReader: LocalCodexCredentialReader(), transport: ChatGPTCodexQuotaTransport())
    // Reuse the last validated catalog when offline; unknown values remain incomplete.
    private let pricingCatalog: PricingCatalog

    init() {
        self.pricingCatalog = PricingCatalogStore().load() ?? PricingCatalog(revision: "unpriced", rates: [:])
        do {
            let ledger = try CodexUsageLedger(); self.ledger = ledger
            self.codex = (try? ledger.today(now: .now)) ?? CodexUsageProjection(inputTokens: 0, cachedInputTokens: 0, outputTokens: 0, cutoff: nil, records: 0, coverage: .empty)
            self.codexRefresh = .success(self.codex, observedAt: .now, cutoff: self.codex.cutoff)
        } catch {
            self.ledger = nil
            self.codex = CodexUsageProjection(inputTokens: 0, cachedInputTokens: 0, outputTokens: 0, cutoff: nil, records: 0, coverage: .accessError("The local usage ledger could not open."))
            self.codexRefresh = ProviderRefreshSnapshot(value: self.codex, state: .unavailable("The local usage ledger could not open."))
        }
    }

    func refreshCodex() {
        guard !isImporting, let ledger else { return }
        isImporting = true
        codexRefresh = .refreshing(retaining: codex)
        let importer = self.importer
        Task {
            do {
                codex = try await Task.detached { try importer.importAvailableSessions(into: ledger) }.value
                codexRefresh = .success(codex, observedAt: .now, cutoff: codex.cutoff)
                refreshPeriod()
                refreshProviderDetails()
            } catch {
                codexRefresh = codexRefresh.failed(observedAt: .now, cutoff: codex.cutoff, error: "Local activity could not be imported.")
                codex = CodexUsageProjection(inputTokens: codex.inputTokens, cachedInputTokens: codex.cachedInputTokens, outputTokens: codex.outputTokens, cutoff: codex.cutoff, records: codex.records, coverage: .accessError("Local activity could not be imported."))
            }
            isImporting = false
        }
    }

    func refreshProviderDetails() {
        guard let ledger else { return }
        let now = Date.now
        let range = UsageDateRange(start: Calendar.current.startOfDay(for: now), end: now)
        Task {
            codexModelTotals = (try? await Task.detached { try ledger.modelTotals(range: range) }.value) ?? codexModelTotals
            codexTrend = (try? await Task.detached { try ledger.trend(range: range, granularity: .hourly) }.value) ?? codexTrend
            if let credential = try? cursorVault.load() {
                cursorModelTotals = (try? await Task.detached { try ledger.modelTotals(range: range, workspaceID: credential.workspaceID) }.value) ?? cursorModelTotals
                cursorTrend = (try? await Task.detached { try ledger.trend(range: range, granularity: .hourly, workspaceID: credential.workspaceID) }.value) ?? cursorTrend
            }
        }
    }

    func refreshPeriod() {
        guard let ledger else { return }
        let period = selectedPeriod
        let now = Date.now
        let calendar = Calendar.current
        let current = period.currentInterval(now: now, calendar: calendar)
        let baseline = period.baselineInterval(now: now, calendar: calendar)
        Task {
            do {
                let currentCodex = try await Task.detached { try ledger.codex(range: UsageDateRange(start: current.start, end: current.end)) }.value
                let baselineCodex = try await Task.detached { try ledger.codex(range: UsageDateRange(start: baseline.start, end: baseline.end)) }.value
                let costing = UsageCosting(catalog: pricingCatalog)
                let currentCodexCost = costing.estimate(try await Task.detached { try ledger.pricingUsage(range: UsageDateRange(start: current.start, end: current.end)) }.value)
                let baselineCodexCost = costing.estimate(try await Task.detached { try ledger.pricingUsage(range: UsageDateRange(start: baseline.start, end: baseline.end)) }.value)
                codexCost = currentCodexCost
                codexForPeriod = currentCodex
                codexComparison = .make(current: currentCodex.totalTokens, baseline: baselineCodex.records == 0 ? nil : baselineCodex.totalTokens, coverage: baselineCodex.records == 0 ? .incomplete("Previous Codex history is unavailable.") : .complete)
                guard let credential = try? cursorVault.load() else {
                    cursorForPeriod = nil
                    cursorComparison = .make(current: 0, baseline: nil, coverage: .unavailable("Cursor history is unavailable."))
                    combinedComparison = .make(current: currentCodex.totalTokens, baseline: nil, coverage: .unavailable("Combined comparison is unavailable until both providers have history."))
                    cursorCost = nil
                    combinedCost = currentCodexCost
                    combinedCostComparison = UsageCostComparison.make(current: currentCodexCost.estimate, baseline: baselineCodexCost.estimate, coverage: .unavailable("Combined cost comparison is unavailable until Cursor history is available."))
                    return
                }
                let currentCursor = try await Task.detached { try ledger.cursor(workspaceID: credential.workspaceID, workspaceName: credential.workspaceName, range: UsageDateRange(start: current.start, end: current.end)) }.value
                let baselineCursor = try await Task.detached { try ledger.cursor(workspaceID: credential.workspaceID, workspaceName: credential.workspaceName, range: UsageDateRange(start: baseline.start, end: baseline.end)) }.value
                let currentCursorCost = costing.estimate(try await Task.detached { try ledger.pricingUsage(range: UsageDateRange(start: current.start, end: current.end), workspaceID: credential.workspaceID) }.value)
                let baselineCursorCost = costing.estimate(try await Task.detached { try ledger.pricingUsage(range: UsageDateRange(start: baseline.start, end: baseline.end), workspaceID: credential.workspaceID) }.value)
                cursorCost = currentCursorCost
                combinedCost = UsageCostResult(estimate: currentCodexCost.estimate + currentCursorCost.estimate, catalogRevision: pricingCatalog.revision, usageRecords: currentCodexCost.usageRecords + currentCursorCost.usageRecords)
                let baselineCombined = UsageCostResult(estimate: baselineCodexCost.estimate + baselineCursorCost.estimate, catalogRevision: pricingCatalog.revision, usageRecords: baselineCodexCost.usageRecords + baselineCursorCost.usageRecords)
                let costCoverage: UsageComparisonCoverage = baselineCodexCost.isComplete && baselineCursorCost.isComplete ? .complete : .incomplete("Cost comparison is incomplete because one or more models are unpriced.")
                combinedCostComparison = UsageCostComparison.make(current: combinedCost!.estimate, baseline: baselineCombined.estimate, coverage: costCoverage)
                cursorForPeriod = currentCursor
                cursorComparison = .make(current: currentCursor.totalTokens, baseline: baselineCursor.cutoff == nil ? nil : baselineCursor.totalTokens, coverage: baselineCursor.cutoff == nil ? .incomplete("Previous Cursor history is unavailable.") : .complete)
                if baselineCodex.records > 0, baselineCursor.cutoff != nil {
                    combinedComparison = .make(current: currentCodex.totalTokens + currentCursor.totalTokens, baseline: baselineCodex.totalTokens + baselineCursor.totalTokens, coverage: .complete)
                } else {
                    combinedComparison = .make(current: currentCodex.totalTokens + currentCursor.totalTokens, baseline: nil, coverage: .unavailable("Combined comparison is unavailable until both providers have history."))
                }
            } catch {
                codexComparison = .make(current: codex.totalTokens, baseline: nil, coverage: .unavailable("Comparison is unavailable."))
                cursorComparison = .make(current: 0, baseline: nil, coverage: .unavailable("Cursor history is unavailable."))
                combinedComparison = .make(current: codex.totalTokens, baseline: nil, coverage: .unavailable("Combined comparison is unavailable."))
                combinedCostComparison = .make(current: CostEstimate(pricedCost: 0, pricedTokens: 0, unpricedTokens: 0, unpricedModels: []), baseline: nil, coverage: .unavailable("Cost comparison is unavailable."))
            }
        }
    }

    func refreshCursor() {
        guard let ledger else { return }
        do {
            guard let credential = try cursorVault.load() else { cursorRefresh = ProviderRefreshSnapshot(value: nil, state: .disconnected); cursor = CursorUsageProjection(inputTokens: 0, cacheReadTokens: 0, cacheWriteTokens: 0, outputTokens: 0, cutoff: nil, workspaceName: nil, coverage: .disconnected); return }
            cursorRefresh = .refreshing(retaining: cursor)
            cursor = CursorUsageProjection(inputTokens: cursor.inputTokens, cacheReadTokens: cursor.cacheReadTokens, cacheWriteTokens: cursor.cacheWriteTokens, outputTokens: cursor.outputTokens, cutoff: cursor.cutoff, workspaceName: credential.workspaceName, coverage: .loading)
            let client = cursorClient
            let quotaClient = cursorQuotaClient
            Task {
                cursorQuota = await quotaClient.refresh(sessionToken: credential.sessionToken)
                do {
                    let events = try await client.fetchToday(sessionToken: credential.sessionToken)
                    try await Task.detached { try ledger.upsertCursor(events, workspaceID: credential.workspaceID) }.value
                    cursor = try await Task.detached { try ledger.cursorToday(workspaceID: credential.workspaceID, workspaceName: credential.workspaceName, now: .now) }.value
                    cursorRefresh = .success(cursor, observedAt: .now, cutoff: cursor.cutoff)
                    refreshProviderDetails()
                } catch CursorUsageClientError.usageEventsUnavailable {
                    cursorRefresh = cursorRefresh.failed(observedAt: .now, cutoff: cursor.cutoff, error: "Cursor did not return timestamped token events for this account.")
                    cursor = CursorUsageProjection(inputTokens: cursor.inputTokens, cacheReadTokens: cursor.cacheReadTokens, cacheWriteTokens: cursor.cacheWriteTokens, outputTokens: cursor.outputTokens, cutoff: cursor.cutoff, workspaceName: credential.workspaceName, coverage: .unavailable("Cursor did not return timestamped token events for this account."))
                } catch {
                    cursorRefresh = cursorRefresh.failed(observedAt: .now, cutoff: cursor.cutoff, error: "Cursor could not refresh its account activity.")
                    cursor = CursorUsageProjection(inputTokens: cursor.inputTokens, cacheReadTokens: cursor.cacheReadTokens, cacheWriteTokens: cursor.cacheWriteTokens, outputTokens: cursor.outputTokens, cutoff: cursor.cutoff, workspaceName: credential.workspaceName, coverage: .unavailable("Cursor could not refresh its account activity."))
                }
            }
        } catch { cursorRefresh = cursorRefresh.failed(observedAt: .now, cutoff: cursor.cutoff, error: "Cursor credentials are unavailable in Keychain."); cursor = CursorUsageProjection(inputTokens: cursor.inputTokens, cacheReadTokens: cursor.cacheReadTokens, cacheWriteTokens: cursor.cacheWriteTokens, outputTokens: cursor.outputTokens, cutoff: cursor.cutoff, workspaceName: cursor.workspaceName, coverage: .unavailable("Cursor credentials are unavailable in Keychain.")) }
    }

    func beginCursorConnection() {
        guard !isConnectingCursor else { return }
        do {
            let authorization = try cursorAuthentication.begin()
            isConnectingCursor = true
            cursorConnectionMessage = "Complete Cursor sign-in in your browser."
            NSWorkspace.shared.open(authorization.browserURL)
            let authentication = cursorAuthentication
            Task {
                do {
                    let session = try await authentication.awaitCompletion(for: authorization)
                    try connectDefaultCursorWorkspace(session)
                } catch { cursorConnectionMessage = error.localizedDescription }
                isConnectingCursor = false
            }
        } catch { cursorConnectionMessage = error.localizedDescription }
    }

    func connectCursorAutomaticallyIfNeeded() {
        guard !didAttemptAutomaticCursorConnection else { return }
        didAttemptAutomaticCursorConnection = true
        guard (try? cursorVault.load()) == nil else { return }
        beginCursorConnection()
    }

    private func connectDefaultCursorWorkspace(_ session: CursorAuthenticatedSession) throws {
        // Cursor's observed usage endpoint is scoped by the authenticated account, not a
        // workspace parameter. Keep a stable local scope key so a later reconnected account
        // cannot be merged with the current ledger, while presenting it as the default scope.
        let scopeID = "default:\(session.accountID)"
        do {
            try cursorVault.save(session.credential(workspaceID: scopeID, workspaceName: "Default workspace"))
            cursorConnectionMessage = "Cursor connected to the default workspace."
            refreshCursor()
        } catch {
            cursorConnectionMessage = "Cursor credentials could not be saved in Keychain."
            throw error
        }
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
