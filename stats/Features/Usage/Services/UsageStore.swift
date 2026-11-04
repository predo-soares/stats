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
    private let codexService: CodexUsageService
    private let cursorService: CursorUsageService
    private let periodService: UsagePeriodService
    private var didAttemptAutomaticCursorConnection = false

    var isCursorConnected: Bool { cursorService.hasCredential() }

    var cursorAccountSummary: String {
        if let name = cursor.workspaceName, isCursorConnected { return name }
        if isConnectingCursor { return "Connecting…" }
        return "Not connected"
    }

    var codexAccountSummary: String {
        switch codexQuota {
        case .published(let snapshot): return snapshot.accountIdentity
        case .awaitingIdentityConfirmation(_, let pending): return pending
        case .authenticationMissing: return "Local device activity"
        case .authenticationExpired: return "Authentication expired"
        case .unavailable: return "Local device activity"
        }
    }

    init(
        ledger: CodexUsageLedger?,
        codexService: CodexUsageService,
        cursorService: CursorUsageService,
        periodService: UsagePeriodService
    ) {
        self.ledger = ledger
        self.codexService = codexService
        self.cursorService = cursorService
        self.periodService = periodService
        if ledger == nil {
            self.codex = CodexUsageProjection(inputTokens: 0, cachedInputTokens: 0, outputTokens: 0, cutoff: nil, records: 0, coverage: .accessError("The local usage ledger could not open."))
            self.codexRefresh = ProviderRefreshSnapshot(value: self.codex, state: .unavailable("The local usage ledger could not open."))
        } else {
            self.codex = CodexUsageProjection(inputTokens: 0, cachedInputTokens: 0, outputTokens: 0, cutoff: nil, records: 0, coverage: .empty)
        }
    }

    func refreshCodex() {
        guard !isImporting, let ledger else { return }
        isImporting = true
        codexRefresh = .refreshing(retaining: codex)
        let service = codexService
        Task {
            do {
                codex = try await service.importToday(into: ledger)
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

    func refreshAll() {
        refreshCodex()
        refreshCursor()
        refreshCodexQuota()
        refreshPeriod()
    }

    func refreshProviderDetails() {
        guard let ledger else { return }
        let service = periodService
        let cursorService = cursorService
        Task {
            let credential = try? cursorService.loadCredential()
            guard let details = try? await service.loadProviderDetails(ledger: ledger, credential: credential) else { return }
            codexModelTotals = details.codexModelTotals
            codexTrend = details.codexTrend
            if credential != nil {
                cursorModelTotals = details.cursorModelTotals
                cursorTrend = details.cursorTrend
            }
        }
    }

    func refreshPeriod() {
        guard let ledger else { return }
        let period = selectedPeriod
        let service = periodService
        let cursorService = cursorService
        Task {
            do {
                let credential = try? cursorService.loadCredential()
                let snapshot = try await service.loadPeriod(ledger: ledger, period: period, credential: credential)
                apply(snapshot)
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
            guard cursorService.hasCredential() else {
                cursorRefresh = ProviderRefreshSnapshot(value: nil, state: .disconnected)
                cursor = CursorUsageProjection(inputTokens: 0, cacheReadTokens: 0, cacheWriteTokens: 0, outputTokens: 0, cutoff: nil, workspaceName: nil, coverage: .disconnected)
                cursorQuota = .unavailable("Cursor quota is not connected.")
                return
            }
            let credential = try cursorService.loadCredential()
            cursorRefresh = .refreshing(retaining: cursor)
            cursor = CursorUsageProjection(inputTokens: cursor.inputTokens, cacheReadTokens: cursor.cacheReadTokens, cacheWriteTokens: cursor.cacheWriteTokens, outputTokens: cursor.outputTokens, cutoff: cursor.cutoff, workspaceName: credential?.workspaceName, coverage: .loading)
            let service = cursorService
            Task {
                do {
                    let result = try await service.refresh(into: ledger)
                    cursorQuota = result.quota
                    cursor = result.projection
                    cursorRefresh = .success(cursor, observedAt: .now, cutoff: cursor.cutoff)
                    refreshProviderDetails()
                    refreshPeriod()
                } catch CursorUsageClientError.usageEventsUnavailable {
                    cursorRefresh = cursorRefresh.failed(observedAt: .now, cutoff: cursor.cutoff, error: "Cursor did not return timestamped token events for this account.")
                    cursor = CursorUsageProjection(inputTokens: cursor.inputTokens, cacheReadTokens: cursor.cacheReadTokens, cacheWriteTokens: cursor.cacheWriteTokens, outputTokens: cursor.outputTokens, cutoff: cursor.cutoff, workspaceName: credential?.workspaceName, coverage: .unavailable("Cursor did not return timestamped token events for this account."))
                } catch CursorUsageClientError.invalidSession {
                    cursorRefresh = ProviderRefreshSnapshot(value: nil, state: .disconnected)
                    cursor = CursorUsageProjection(inputTokens: 0, cacheReadTokens: 0, cacheWriteTokens: 0, outputTokens: 0, cutoff: nil, workspaceName: nil, coverage: .disconnected)
                    cursorQuota = .unavailable("Cursor quota is not connected.")
                } catch {
                    cursorRefresh = cursorRefresh.failed(observedAt: .now, cutoff: cursor.cutoff, error: "Cursor could not refresh its account activity.")
                    cursor = CursorUsageProjection(inputTokens: cursor.inputTokens, cacheReadTokens: cursor.cacheReadTokens, cacheWriteTokens: cursor.cacheWriteTokens, outputTokens: cursor.outputTokens, cutoff: cursor.cutoff, workspaceName: credential?.workspaceName, coverage: .unavailable("Cursor could not refresh its account activity."))
                }
            }
        } catch {
            cursorRefresh = cursorRefresh.failed(observedAt: .now, cutoff: cursor.cutoff, error: "Cursor credentials are unavailable in Keychain.")
            cursor = CursorUsageProjection(inputTokens: cursor.inputTokens, cacheReadTokens: cursor.cacheReadTokens, cacheWriteTokens: cursor.cacheWriteTokens, outputTokens: cursor.outputTokens, cutoff: cursor.cutoff, workspaceName: cursor.workspaceName, coverage: .unavailable("Cursor credentials are unavailable in Keychain."))
        }
    }

    func beginCursorConnection() {
        guard !isConnectingCursor else { return }
        do {
            let authorization = try cursorService.beginAuthorization()
            isConnectingCursor = true
            cursorConnectionMessage = "Complete Cursor sign-in in your browser."
            NSWorkspace.shared.open(authorization.browserURL)
            let service = cursorService
            Task {
                do {
                    let session = try await service.awaitAuthorization(authorization)
                    try service.saveDefaultWorkspace(session)
                    cursorConnectionMessage = "Cursor connected to the default workspace."
                    refreshCursor()
                } catch {
                    cursorConnectionMessage = error.localizedDescription
                }
                isConnectingCursor = false
            }
        } catch {
            cursorConnectionMessage = error.localizedDescription
        }
    }

    func disconnectCursor() {
        do {
            try cursorService.disconnect()
            cursorConnectionMessage = "Cursor disconnected."
            cursorRefresh = ProviderRefreshSnapshot(value: nil, state: .disconnected)
            cursor = CursorUsageProjection(inputTokens: 0, cacheReadTokens: 0, cacheWriteTokens: 0, outputTokens: 0, cutoff: nil, workspaceName: nil, coverage: .disconnected)
            cursorQuota = .unavailable("Cursor quota is not connected.")
            cursorForPeriod = nil
            cursorModelTotals = []
            cursorTrend = []
            refreshPeriod()
        } catch {
            cursorConnectionMessage = "Cursor credentials could not be removed from Keychain."
        }
    }

    func connectCursorAutomaticallyIfNeeded() {
        guard !didAttemptAutomaticCursorConnection else { return }
        didAttemptAutomaticCursorConnection = true
        guard !cursorService.hasCredential() else { return }
        beginCursorConnection()
    }

    func refreshCodexQuota() {
        let service = codexService
        let retained: CodexQuotaSnapshot?
        let identity: String?
        if case let .published(snapshot) = codexQuota { retained = snapshot; identity = snapshot.accountIdentity }
        else { retained = nil; identity = nil }
        Task { codexQuota = await service.refreshQuota(confirmedIdentity: identity, retained: retained) }
    }

    private func apply(_ snapshot: UsagePeriodSnapshot) {
        codexForPeriod = snapshot.codexForPeriod
        cursorForPeriod = snapshot.cursorForPeriod
        codexComparison = snapshot.codexComparison
        cursorComparison = snapshot.cursorComparison
        combinedComparison = snapshot.combinedComparison
        codexCost = snapshot.codexCost
        cursorCost = snapshot.cursorCost
        combinedCost = snapshot.combinedCost
        combinedCostComparison = snapshot.combinedCostComparison
    }
}
