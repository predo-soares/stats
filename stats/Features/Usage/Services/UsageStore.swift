import AppKit
import Foundation
import Observation

@MainActor @Observable final class UsageStore {
    private var enrollment = ProviderEnrollmentStore()
    private var isBootstrappingEnrollment = true

    var needsProviderEnrollment: Bool {
        !enrollment.hasCompletedEnrollment
    }

    var codexConnectionEnabled = false {
        didSet {
            UserDefaults.standard.set(codexConnectionEnabled, forKey: "usage.connection.codex")
            enrollment.setEnabled(codexConnectionEnabled, for: .codex)
            guard !isBootstrappingEnrollment, codexConnectionEnabled else { return }
            refreshCodex()
            refreshCodexQuota()
        }
    }
    var cursorConnectionEnabled = false {
        didSet {
            UserDefaults.standard.set(cursorConnectionEnabled, forKey: "usage.connection.cursor")
            enrollment.setEnabled(cursorConnectionEnabled, for: .cursor)
            guard !isBootstrappingEnrollment, cursorConnectionEnabled else { return }
            if isCursorConnected { refreshCursor() } else { beginCursorConnection() }
        }
    }
    var claudeConnectionEnabled = false {
        didSet {
            UserDefaults.standard.set(claudeConnectionEnabled, forKey: "usage.connection.claude")
            enrollment.setEnabled(claudeConnectionEnabled, for: .claude)
            guard !isBootstrappingEnrollment, claudeConnectionEnabled else { return }
            refreshClaude()
        }
    }
    var piConnectionEnabled = false {
        didSet {
            UserDefaults.standard.set(piConnectionEnabled, forKey: "usage.connection.pi")
            enrollment.setEnabled(piConnectionEnabled, for: .pi)
            guard !isBootstrappingEnrollment, piConnectionEnabled else { return }
            refreshPi()
        }
    }
    var grokConnectionEnabled = false {
        didSet {
            UserDefaults.standard.set(grokConnectionEnabled, forKey: "usage.connection.grok")
            enrollment.setEnabled(grokConnectionEnabled, for: .grok)
            guard !isBootstrappingEnrollment, grokConnectionEnabled else { return }
            refreshGrok()
        }
    }
    var zaiConnectionEnabled = false {
        didSet {
            UserDefaults.standard.set(zaiConnectionEnabled, forKey: "usage.connection.zai")
            enrollment.setEnabled(zaiConnectionEnabled, for: .zai)
            guard !isBootstrappingEnrollment, zaiConnectionEnabled else { return }
            refreshZai()
        }
    }
    var codex: CodexUsageProjection
    var claude = LocalUsageProjection.empty()
    var pi = LocalUsageProjection.empty()
    var grok = LocalUsageProjection.empty()
    var zai = LocalUsageProjection.empty()
    var cursor = CursorUsageProjection(inputTokens: 0, cacheReadTokens: 0, cacheWriteTokens: 0, outputTokens: 0, cutoff: nil, workspaceName: nil, coverage: .disconnected)
    var codexQuota: CodexQuotaPublication = .authenticationMissing
    private(set) var lastPublishedCodexQuota: CodexQuotaSnapshot?
    var cursorQuota: CursorQuotaPublication = .unavailable("Cursor quota is not connected.")
    var cursorConnectionMessage: String?
    var isConnectingCursor = false
    var pendingCursorWorkspaceScopes: [CursorWorkspaceScope] = []
    private var pendingCursorSession: CursorAuthenticatedSession?
    var isImporting = false
    private var confirmedCodexIdentity: String? {
        get { UserDefaults.standard.string(forKey: "codex.confirmedIdentity") }
        set { UserDefaults.standard.set(newValue, forKey: "codex.confirmedIdentity") }
    }

    var needsCodexIdentityConfirmation: Bool {
        if case .awaitingIdentityConfirmation = codexQuota { return true }
        return false
    }
    var selectedPeriod: UsageComparisonPeriod = .today
    var codexForPeriod: CodexUsageProjection?
    var cursorForPeriod: CursorUsageProjection?
    var codexComparison = UsageTokenComparison.make(current: 0, baseline: nil, coverage: .unavailable("Comparison is not ready."))
    var cursorComparison = UsageTokenComparison.make(current: 0, baseline: nil, coverage: .unavailable("Comparison is not ready."))
    var combinedComparison = UsageTokenComparison.make(current: 0, baseline: nil, coverage: .unavailable("Comparison is not ready."))
    var codexCost: UsageCostResult?
    var cursorCost: UsageCostResult?
    var claudeCost: UsageCostResult?
    var piCost: UsageCostResult?
    var grokCost: UsageCostResult?
    var zaiCost: UsageCostResult?
    var combinedCost: UsageCostResult?
    var combinedCostComparison = UsageCostComparison.make(current: CostEstimate(pricedCost: 0, pricedTokens: 0, unpricedTokens: 0, unpricedModels: []), baseline: nil, coverage: .unavailable("Cost comparison is not ready."))
    var codexModelTotals: [UsageModelTotal] = []
    var cursorModelTotals: [UsageModelTotal] = []
    var claudeModelTotals: [UsageModelTotal] = []
    var piModelTotals: [UsageModelTotal] = []
    var grokModelTotals: [UsageModelTotal] = []
    var zaiModelTotals: [UsageModelTotal] = []
    var codexTrend: [UsageTrendBucket] = []
    var cursorTrend: [UsageTrendBucket] = []
    var claudeTrend: [UsageTrendBucket] = []
    var piTrend: [UsageTrendBucket] = []
    var grokTrend: [UsageTrendBucket] = []
    var zaiTrend: [UsageTrendBucket] = []
    private(set) var lastRefreshAt: Date? = UserDefaults.standard.object(forKey: "usage.lastRefreshAt") as? Date
    private(set) var codexRefresh = ProviderRefreshSnapshot<CodexUsageProjection>(value: nil, state: .disconnected)
    private(set) var cursorRefresh = ProviderRefreshSnapshot<CursorUsageProjection>(value: nil, state: .disconnected)
    private(set) var claudeRefresh = ProviderRefreshSnapshot<LocalUsageProjection>(value: nil, state: .disconnected)
    private(set) var piRefresh = ProviderRefreshSnapshot<LocalUsageProjection>(value: nil, state: .disconnected)
    private(set) var grokRefresh = ProviderRefreshSnapshot<LocalUsageProjection>(value: nil, state: .disconnected)
    private(set) var zaiRefresh = ProviderRefreshSnapshot<LocalUsageProjection>(value: nil, state: .disconnected)
    private(set) var cursorLastSuccessfulRefreshAt: Date?
    private(set) var claudeLastSuccessfulRefreshAt: Date?
    private(set) var piLastSuccessfulRefreshAt: Date?
    private(set) var grokLastSuccessfulRefreshAt: Date?
    private(set) var zaiLastSuccessfulRefreshAt: Date?
    var piUnderlyingProviders: [String] = []
    var claudeSourceEvidence: LocalSourceEvidence?
    var claudeSourceEvidenceError: String?
    var isLoadingClaudeSourceEvidence = false
    var piSourceEvidence: LocalSourceEvidence?
    var piSourceEvidenceError: String?
    var isLoadingPiSourceEvidence = false
    var grokSourceEvidence: LocalSourceEvidence?
    var grokSourceEvidenceError: String?
    var zaiSourceEvidence: LocalSourceEvidence?
    var cursorSourceEvidence: CursorSourceEvidence?
    var cursorSourceEvidenceError: String?
    var isLoadingCursorSourceEvidence = false

    private let ledger: CodexUsageLedger?
    private let codexService: CodexUsageService
    private let cursorService: CursorUsageService
    private let claudeService: ClaudeUsageService
    private let piService: PiUsageService
    private let grokImporter: GrokUsageImporter
    private let zaiImporter: ZaiUsageImporter
    private let periodService: UsagePeriodService
    private var didAttemptAutomaticCursorConnection = false
    private(set) var cursorCredentialIsAvailable = false

    /// Keychain changes are external to SwiftUI observation. This store-owned value is updated at
    /// the authentication boundary so settings immediately reflects Connect/Disconnect actions.
    var isCursorConnected: Bool { cursorCredentialIsAvailable }

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
        claudeService: ClaudeUsageService,
        piService: PiUsageService,
        grokImporter: GrokUsageImporter = GrokUsageImporter(),
        zaiImporter: ZaiUsageImporter = ZaiUsageImporter(),
        periodService: UsagePeriodService
    ) {
        self.ledger = ledger
        self.codexService = codexService
        self.cursorService = cursorService
        self.claudeService = claudeService
        self.piService = piService
        self.grokImporter = grokImporter
        self.zaiImporter = zaiImporter
        self.periodService = periodService
        self.cursorCredentialIsAvailable = cursorService.hasCredential()
        if ledger == nil {
            self.codex = CodexUsageProjection(inputTokens: 0, cachedInputTokens: 0, outputTokens: 0, cutoff: nil, records: 0, coverage: .accessError("The local usage ledger could not open."))
            self.codexRefresh = ProviderRefreshSnapshot(value: self.codex, state: .unavailable("The local usage ledger could not open."))
        } else {
            self.codex = CodexUsageProjection(inputTokens: 0, cachedInputTokens: 0, outputTokens: 0, cutoff: nil, records: 0, coverage: .empty)
        }

        let hasPriorUsage =
            UserDefaults.standard.object(forKey: "usage.lastRefreshAt") != nil
            || self.cursorCredentialIsAvailable
        let enrollmentStore = ProviderEnrollmentStore()
        enrollmentStore.migrateLegacyConnectionsIfNeeded(hasPriorUsage: hasPriorUsage)
        self.enrollment = enrollmentStore
        if enrollmentStore.hasCompletedEnrollment {
            self.codexConnectionEnabled = enrollmentStore.isEnabled(.codex)
            self.cursorConnectionEnabled = enrollmentStore.isEnabled(.cursor)
            self.claudeConnectionEnabled = enrollmentStore.isEnabled(.claude)
            self.piConnectionEnabled = enrollmentStore.isEnabled(.pi)
            self.grokConnectionEnabled = enrollmentStore.isEnabled(.grok)
            self.zaiConnectionEnabled = enrollmentStore.isEnabled(.zai)
        } else {
            if let codex = UserDefaults.standard.object(forKey: "usage.connection.codex") as? Bool {
                self.codexConnectionEnabled = codex
            }
            if let cursor = UserDefaults.standard.object(forKey: "usage.connection.cursor") as? Bool {
                self.cursorConnectionEnabled = cursor
            }
            if let claude = UserDefaults.standard.object(forKey: "usage.connection.claude") as? Bool {
                self.claudeConnectionEnabled = claude
            }
            if let pi = UserDefaults.standard.object(forKey: "usage.connection.pi") as? Bool {
                self.piConnectionEnabled = pi
            }
            if let grok = UserDefaults.standard.object(forKey: "usage.connection.grok") as? Bool {
                self.grokConnectionEnabled = grok
            }
            if let zai = UserDefaults.standard.object(forKey: "usage.connection.zai") as? Bool {
                self.zaiConnectionEnabled = zai
            }
        }
        if ledger == nil {
            self.claude = LocalUsageProjection.empty(coverage: .accessError("The local usage ledger could not open."))
            self.claudeRefresh = ProviderRefreshSnapshot(value: self.claude, state: .unavailable("The local usage ledger could not open."))
            self.pi = LocalUsageProjection.empty(coverage: .accessError("The local usage ledger could not open."))
            self.piRefresh = ProviderRefreshSnapshot(value: self.pi, state: .unavailable("The local usage ledger could not open."))
            self.grok = LocalUsageProjection.empty(coverage: .accessError("The local usage ledger could not open."))
            self.grokRefresh = ProviderRefreshSnapshot(value: self.grok, state: .unavailable("The local usage ledger could not open."))
            self.zai = LocalUsageProjection.empty(coverage: .accessError("The local usage ledger could not open."))
            self.zaiRefresh = ProviderRefreshSnapshot(value: self.zai, state: .unavailable("The local usage ledger could not open."))
        }
        self.isBootstrappingEnrollment = false
    }

    func isProviderEnrolled(_ provider: UsageProviderIdentity) -> Bool {
        switch provider {
        case .codex: codexConnectionEnabled
        case .cursor: cursorConnectionEnabled
        case .claude: claudeConnectionEnabled
        case .pi: piConnectionEnabled
        case .grok: grokConnectionEnabled
        case .zai: zaiConnectionEnabled
        }
    }

    func setProviderEnrolled(_ provider: UsageProviderIdentity, enabled: Bool) {
        switch provider {
        case .codex: codexConnectionEnabled = enabled
        case .cursor: cursorConnectionEnabled = enabled
        case .claude: claudeConnectionEnabled = enabled
        case .pi: piConnectionEnabled = enabled
        case .grok: grokConnectionEnabled = enabled
        case .zai: zaiConnectionEnabled = enabled
        }
    }

    func completeProviderEnrollment(_ selection: Set<UsageProviderIdentity>) {
        enrollment.finish(with: selection)
        codexConnectionEnabled = selection.contains(.codex)
        cursorConnectionEnabled = selection.contains(.cursor)
        claudeConnectionEnabled = selection.contains(.claude)
        piConnectionEnabled = selection.contains(.pi)
        grokConnectionEnabled = selection.contains(.grok)
        zaiConnectionEnabled = selection.contains(.zai)
    }

    func skipProviderEnrollment() {
        enrollment.skipSelectingNone()
        codexConnectionEnabled = false
        cursorConnectionEnabled = false
        claudeConnectionEnabled = false
        piConnectionEnabled = false
        grokConnectionEnabled = false
        zaiConnectionEnabled = false
    }

    func supportState(for provider: UsageProviderIdentity) -> ProviderSupportState {
        provider.supportState
    }

    func unavailableMessage(for provider: UsageProviderIdentity) -> String? {
        switch provider {
        case .codex:
            if !codexConnectionEnabled { return "Codex is paused in Settings." }
            return codexRefresh.state.errorMessage
        case .cursor:
            if !cursorConnectionEnabled { return "Cursor is paused in Settings." }
            return cursorRefresh.state.errorMessage
        case .claude:
            if !claudeConnectionEnabled { return "Claude is paused in Settings." }
            return claudeRefresh.state.errorMessage
        case .pi:
            if !piConnectionEnabled { return "Pi is paused in Settings." }
            return piRefresh.state.errorMessage
        case .grok:
            if !grokConnectionEnabled { return "Grok is paused in Settings." }
            return grokRefresh.state.errorMessage
        case .zai:
            if !zaiConnectionEnabled { return "Z.ai is paused in Settings." }
            return zaiRefresh.state.errorMessage
        }
    }

    func refreshCodex() {
        guard codexConnectionEnabled, !isImporting, let ledger else { return }
        isImporting = true
        codexRefresh = .refreshing(retaining: codex)
        codex = CodexUsageProjection(
            inputTokens: codex.inputTokens,
            cachedInputTokens: codex.cachedInputTokens,
            outputTokens: codex.outputTokens,
            cutoff: codex.cutoff,
            records: codex.records,
            coverage: .importing
        )
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
        markRefresh()
        refreshCodex()
        refreshCursor()
        refreshClaude()
        refreshPi()
        refreshGrok()
        refreshZai()
        refreshCodexQuota()
        refreshPeriod()
    }

    func refreshClaude() {
        guard claudeConnectionEnabled, let ledger else { return }
        claudeRefresh = .refreshing(retaining: claude)
        claude = LocalUsageProjection(
            inputTokens: claude.inputTokens,
            cachedInputTokens: claude.cachedInputTokens,
            cacheCreationTokens: claude.cacheCreationTokens,
            outputTokens: claude.outputTokens,
            reasoningTokens: claude.reasoningTokens,
            cutoff: claude.cutoff,
            records: claude.records,
            coverage: .importing
        )
        let service = claudeService
        let periodService = periodService
        Task {
            do {
                let result = try await service.refresh(into: ledger)
                claude = result.projection
                claudeSourceEvidence = result.evidence
                claudeLastSuccessfulRefreshAt = .now
                claudeRefresh = .success(claude, observedAt: .now, cutoff: claude.cutoff)
                claudeCost = try await periodService.estimateLocalCost(ledger: ledger, provider: .claude)
                refreshProviderDetails()
            } catch {
                claudeRefresh = claudeRefresh.failed(observedAt: .now, cutoff: claude.cutoff, error: "Claude local activity could not be refreshed.")
                claude = LocalUsageProjection(
                    inputTokens: claude.inputTokens,
                    cachedInputTokens: claude.cachedInputTokens,
                    cacheCreationTokens: claude.cacheCreationTokens,
                    outputTokens: claude.outputTokens,
                    reasoningTokens: claude.reasoningTokens,
                    cutoff: claude.cutoff,
                    records: claude.records,
                    coverage: .accessError("Claude local activity could not be refreshed.")
                )
            }
        }
    }




    func refreshZai() {
        guard zaiConnectionEnabled, let ledger else { return }
        zaiRefresh = .refreshing(retaining: zai)
        let importer = zaiImporter
        let service = ExperimentalLocalUsageService(kind: .zai)
        let periodService = periodService
        Task {
            do {
                let hasKey = ZaiCredentialVault.hasCredential()
                let events = try importer.importEvents(usingCredentialPresent: hasKey)
                let (projection, evidence) = try await service.refresh(into: ledger, events: events)
                zai = projection
                zaiSourceEvidence = evidence
                zaiLastSuccessfulRefreshAt = .now
                zaiRefresh = .success(zai, observedAt: .now, cutoff: zai.cutoff)
                zaiCost = try await periodService.estimateLocalCost(ledger: ledger, provider: .zai)
                let today = UsageDateRange(start: Calendar.current.startOfDay(for: .now), end: .now)
                zaiModelTotals = (try? await ledger.localModelTotals(provider: .zai, range: today)) ?? []
                zaiTrend = (try? await ledger.localTrend(provider: .zai, range: today, granularity: .hourly)) ?? []
                refreshProviderDetails()
            } catch {
                let (projection, evidence) = try await service.preserveFailure(
                    into: ledger,
                    coverage: .unavailable("Z.ai credential or usage bundle is unavailable."),
                    outcome: .sourceMissing,
                    safeErrorReason: "Z.ai requires an explicit Keychain credential before fixture/API import."
                )
                zai = projection
                zaiSourceEvidence = evidence
                zaiRefresh = .success(zai, observedAt: .now, cutoff: zai.cutoff)
                zaiModelTotals = []
                zaiTrend = []
            }
        }
    }

    func saveZaiAPIKey(_ key: String) {
        try? ZaiCredentialVault.save(key)
        if zaiConnectionEnabled { refreshZai() }
    }

    func clearZaiAPIKey() {
        ZaiCredentialVault.delete()
        if zaiConnectionEnabled { refreshZai() }
    }

    func refreshGrok() {
        guard grokConnectionEnabled, let ledger else { return }
        grokRefresh = .refreshing(retaining: grok)
        grok = LocalUsageProjection(
            inputTokens: grok.inputTokens,
            cachedInputTokens: grok.cachedInputTokens,
            cacheCreationTokens: grok.cacheCreationTokens,
            outputTokens: grok.outputTokens,
            reasoningTokens: grok.reasoningTokens,
            cutoff: grok.cutoff,
            records: grok.records,
            coverage: .importing
        )
        let importer = grokImporter
        let service = ExperimentalLocalUsageService(kind: .grok)
        let periodService = periodService
        Task {
            do {
                let events = try importer.importEvents()
                let (projection, evidence) = try await service.refresh(into: ledger, events: events)
                grok = projection
                grokSourceEvidence = evidence
                grokLastSuccessfulRefreshAt = .now
                grokRefresh = .success(grok, observedAt: .now, cutoff: grok.cutoff)
                grokCost = try await periodService.estimateLocalCost(ledger: ledger, provider: .grok)
                refreshProviderDetails()
            } catch GrokUsageImporter.ImportError.sourceMissing {
                let (projection, evidence) = try await service.preserveFailure(
                    into: ledger,
                    coverage: .unavailable("Grok local sessions were not found on this Mac."),
                    outcome: .sourceMissing,
                    safeErrorReason: "Local Grok sessions directory is missing."
                )
                grok = projection
                grokSourceEvidence = evidence
                grokRefresh = .success(grok, observedAt: .now, cutoff: grok.cutoff)
            } catch {
                grokRefresh = grokRefresh.failed(observedAt: .now, cutoff: grok.cutoff, error: "Grok local activity could not be refreshed.")
                grok = LocalUsageProjection(
                    inputTokens: grok.inputTokens,
                    cachedInputTokens: grok.cachedInputTokens,
                    cacheCreationTokens: grok.cacheCreationTokens,
                    outputTokens: grok.outputTokens,
                    reasoningTokens: grok.reasoningTokens,
                    cutoff: grok.cutoff,
                    records: grok.records,
                    coverage: .accessError("Grok local activity could not be refreshed.")
                )
            }
        }
    }

    func refreshPi() {
        guard piConnectionEnabled, let ledger else { return }
        piRefresh = .refreshing(retaining: pi)
        pi = LocalUsageProjection(
            inputTokens: pi.inputTokens,
            cachedInputTokens: pi.cachedInputTokens,
            cacheCreationTokens: pi.cacheCreationTokens,
            outputTokens: pi.outputTokens,
            reasoningTokens: pi.reasoningTokens,
            cutoff: pi.cutoff,
            records: pi.records,
            coverage: .importing
        )
        let service = piService
        let periodService = periodService
        Task {
            do {
                let result = try await service.refresh(into: ledger)
                pi = result.projection
                piSourceEvidence = result.evidence
                piUnderlyingProviders = result.underlyingProviders
                piLastSuccessfulRefreshAt = .now
                piRefresh = .success(pi, observedAt: .now, cutoff: pi.cutoff)
                piCost = try await periodService.estimateLocalCost(ledger: ledger, provider: .pi)
                refreshProviderDetails()
            } catch {
                piRefresh = piRefresh.failed(observedAt: .now, cutoff: pi.cutoff, error: "Pi local activity could not be refreshed.")
                pi = LocalUsageProjection(
                    inputTokens: pi.inputTokens,
                    cachedInputTokens: pi.cachedInputTokens,
                    cacheCreationTokens: pi.cacheCreationTokens,
                    outputTokens: pi.outputTokens,
                    reasoningTokens: pi.reasoningTokens,
                    cutoff: pi.cutoff,
                    records: pi.records,
                    coverage: .accessError("Pi local activity could not be refreshed.")
                )
            }
        }
    }

    func loadClaudeSourceEvidence() {
        guard !isLoadingClaudeSourceEvidence, let ledger, claudeConnectionEnabled else {
            claudeSourceEvidence = nil
            claudeSourceEvidenceError = claudeConnectionEnabled ? nil : "Enable Claude in Settings to inspect source evidence."
            return
        }
        isLoadingClaudeSourceEvidence = true
        claudeSourceEvidenceError = nil
        let service = claudeService
        Task {
            do {
                let result = try await service.refresh(into: ledger, preserveOnFailure: true)
                claudeSourceEvidence = result.evidence
            } catch {
                claudeSourceEvidence = nil
                claudeSourceEvidenceError = "Claude source evidence could not be read from the local ledger."
            }
            isLoadingClaudeSourceEvidence = false
        }
    }

    private func markRefresh() {
        let now = Date.now
        lastRefreshAt = now
        UserDefaults.standard.set(now, forKey: "usage.lastRefreshAt")
    }

    func loadCursorSourceEvidence() {
        guard !isLoadingCursorSourceEvidence, let ledger else { return }
        guard let credential = try? cursorService.loadCredential() else {
            cursorSourceEvidence = nil
            cursorSourceEvidenceError = "Connect Cursor to inspect its source evidence."
            return
        }
        isLoadingCursorSourceEvidence = true
        cursorSourceEvidenceError = nil
        let service = cursorService
        Task {
            do {
                let probe = await service.probeToday()
                let snapshot = try await ledger.cursorSourceEvidence(workspaceID: credential.workspaceID)
                cursorSourceEvidence = CursorSourceEvidence(
                    accountFingerprint: credential.redactedAccountFingerprint,
                    generatedAt: .now,
                    currentProbe: probe,
                    windows: snapshot.windows,
                    importRanges: snapshot.importRanges
                )
            } catch {
                cursorSourceEvidence = nil
                cursorSourceEvidenceError = "Cursor source evidence could not be read from the local ledger."
            }
            isLoadingCursorSourceEvidence = false
        }
    }

    func refreshProviderDetails() {
        guard let ledger else { return }
        let service = periodService
        let cursorService = cursorService
        Task {
            let credential = try? cursorService.loadCredential()
            guard let details = try? await service.loadProviderDetails(
                ledger: ledger,
                credential: credential,
                includeClaude: claudeConnectionEnabled,
                includePi: piConnectionEnabled
            ) else { return }
            codexModelTotals = details.codexModelTotals
            codexTrend = details.codexTrend
            if credential != nil {
                cursorModelTotals = details.cursorModelTotals
                cursorTrend = details.cursorTrend
            }
            if claudeConnectionEnabled {
                claudeModelTotals = details.claudeModelTotals
                claudeTrend = details.claudeTrend
            } else {
                claudeModelTotals = []
                claudeTrend = []
            }
            if piConnectionEnabled {
                piModelTotals = details.piModelTotals
                piTrend = details.piTrend
            } else {
                piModelTotals = []
                piTrend = []
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
        guard cursorConnectionEnabled, let ledger else { return }
        do {
            guard cursorService.hasCredential() else {
                cursorCredentialIsAvailable = false
                cursorRefresh = ProviderRefreshSnapshot(value: nil, state: .disconnected)
                cursorLastSuccessfulRefreshAt = nil
                cursor = CursorUsageProjection(inputTokens: 0, cacheReadTokens: 0, cacheWriteTokens: 0, outputTokens: 0, cutoff: nil, workspaceName: nil, coverage: .disconnected)
                cursorQuota = .unavailable("Cursor quota is not connected.")
                return
            }
            cursorCredentialIsAvailable = true
            let credential = try cursorService.loadCredential()
            cursorRefresh = .refreshing(retaining: cursor)
            cursor = CursorUsageProjection(inputTokens: cursor.inputTokens, cacheReadTokens: cursor.cacheReadTokens, cacheWriteTokens: cursor.cacheWriteTokens, outputTokens: cursor.outputTokens, cutoff: cursor.cutoff, workspaceName: credential?.workspaceName, coverage: .loading)
            let service = cursorService
            let store = self
            Task {
                do {
                    let result = try await service.refresh(into: ledger) { projection in
                        await store.publishCursorImportProgress(projection)
                    }
                    cursorQuota = result.quota
                    cursor = result.projection
                    cursorLastSuccessfulRefreshAt = .now
                    cursorRefresh = .success(cursor, observedAt: .now, cutoff: cursor.cutoff)
                    refreshProviderDetails()
                    refreshPeriod()
                } catch CursorUsageClientError.usageEventsUnavailable {
                    cursorRefresh = cursorRefresh.failed(observedAt: .now, cutoff: cursor.cutoff, error: "Cursor did not return timestamped token events for this account.")
                    cursor = CursorUsageProjection(inputTokens: cursor.inputTokens, cacheReadTokens: cursor.cacheReadTokens, cacheWriteTokens: cursor.cacheWriteTokens, outputTokens: cursor.outputTokens, cutoff: cursor.cutoff, workspaceName: credential?.workspaceName, coverage: .unavailable("Cursor did not return timestamped token events for this account."))
                } catch CursorUsageClientError.invalidSession {
                    cursorRefresh = ProviderRefreshSnapshot(value: nil, state: .disconnected)
                    cursorLastSuccessfulRefreshAt = nil
                    cursor = CursorUsageProjection(inputTokens: 0, cacheReadTokens: 0, cacheWriteTokens: 0, outputTokens: 0, cutoff: nil, workspaceName: nil, coverage: .disconnected)
                    cursorQuota = .unavailable("Cursor quota is not connected.")
                } catch {
                    let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                    cursorRefresh = cursorRefresh.failed(observedAt: .now, cutoff: cursor.cutoff, error: message)
                    cursor = CursorUsageProjection(inputTokens: cursor.inputTokens, cacheReadTokens: cursor.cacheReadTokens, cacheWriteTokens: cursor.cacheWriteTokens, outputTokens: cursor.outputTokens, cutoff: cursor.cutoff, workspaceName: credential?.workspaceName, coverage: .unavailable(message))
                }
            }
        } catch {
            cursorRefresh = cursorRefresh.failed(observedAt: .now, cutoff: cursor.cutoff, error: "Cursor credentials are unavailable in Keychain.")
            cursor = CursorUsageProjection(inputTokens: cursor.inputTokens, cacheReadTokens: cursor.cacheReadTokens, cacheWriteTokens: cursor.cacheWriteTokens, outputTokens: cursor.outputTokens, cutoff: cursor.cutoff, workspaceName: cursor.workspaceName, coverage: .unavailable("Cursor credentials are unavailable in Keychain."))
        }
    }

    func beginCursorConnection() {
        guard cursorConnectionEnabled, !isConnectingCursor else { return }
        do {
            let authorization = try cursorService.beginAuthorization()
            isConnectingCursor = true
            cursorConnectionMessage = "Complete Cursor sign-in in your browser."
            NSWorkspace.shared.open(authorization.browserURL)
            let service = cursorService
            Task {
                do {
                    let session = try await service.awaitAuthorization(authorization)
                    try await finishCursorConnection(session: session, preferredWorkspaceID: nil)
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
            cursorCredentialIsAvailable = false
            cursorConnectionMessage = "Cursor disconnected."
            pendingCursorWorkspaceScopes = []
            pendingCursorSession = nil
            cursorRefresh = ProviderRefreshSnapshot(value: nil, state: .disconnected)
            cursorLastSuccessfulRefreshAt = nil
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

    func selectPendingCursorWorkspace(_ scope: CursorWorkspaceScope) {
        guard let session = pendingCursorSession else { return }
        Task {
            do {
                try await finishCursorConnection(session: session, preferredWorkspaceID: scope.id)
            } catch {
                cursorConnectionMessage = error.localizedDescription
            }
        }
    }

    private func finishCursorConnection(session: CursorAuthenticatedSession, preferredWorkspaceID: String?) async throws {
        do {
            let credential = try await cursorService.connect(session: session, preferredWorkspaceID: preferredWorkspaceID)
            cursorCredentialIsAvailable = true
            pendingCursorSession = nil
            pendingCursorWorkspaceScopes = []
            cursorConnectionMessage = "Cursor connected to \(credential.workspaceName)."
            refreshCursor()
        } catch CursorWorkspaceScopeError.ambiguousSelection(let scopes) {
            pendingCursorSession = session
            pendingCursorWorkspaceScopes = scopes
            cursorConnectionMessage = "Select one Cursor workspace before continuing."
        } catch CursorWorkspaceScopeError.unknownScope {
            cursorConnectionMessage = CursorUsageClientError.rejectedScope.localizedDescription
            throw CursorUsageClientError.rejectedScope
        }
    }

    func connectCursorAutomaticallyIfNeeded() {
        guard cursorConnectionEnabled, !didAttemptAutomaticCursorConnection else { return }
        didAttemptAutomaticCursorConnection = true
        guard !cursorService.hasCredential() else { return }
        beginCursorConnection()
    }

    func refreshCodexQuota() {
        guard codexConnectionEnabled else { return }
        let service = codexService
        let retained = lastPublishedCodexQuota
        let identity = confirmedCodexIdentity
        Task {
            let publication = await service.refreshQuota(confirmedIdentity: identity, retained: retained)
            if case let .published(snapshot) = publication {
                lastPublishedCodexQuota = snapshot
                if confirmedCodexIdentity == nil {
                    confirmedCodexIdentity = snapshot.accountIdentity
                }
            }
            codexQuota = publication
        }
    }

    func confirmCodexAccountIdentity() {
        guard case let .awaitingIdentityConfirmation(_, pending) = codexQuota else { return }
        confirmedCodexIdentity = pending
        refreshCodexQuota()
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

    private func publishCursorImportProgress(_ projection: CursorUsageProjection) {
        cursor = projection
        cursorRefresh = .refreshing(retaining: projection)
        refreshProviderDetails()
        refreshPeriod()
    }
}
