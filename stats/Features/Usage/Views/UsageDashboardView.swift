import SwiftUI

struct UsageDashboardView: View {
    @Bindable var store: UsageStore
    @AppStorage("usage.metric") private var metric: UsageMetric = .tokens
    @AppStorage("usage.period") private var periodRawValue: String = UsageComparisonPeriod.today.rawValue
    @State private var codexDetailsExpanded = false
    @State private var cursorDetailsExpanded = false
    @State private var claudeDetailsExpanded = false
    @State private var piDetailsExpanded = false
    @State private var grokDetailsExpanded = false
    @State private var zaiDetailsExpanded = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    summary
                    codexCard
                    cursorCard
                    if store.claudeConnectionEnabled { claudeCard }
                    if store.piConnectionEnabled { piCard }
                    if store.grokConnectionEnabled { grokCard }
                    if store.zaiConnectionEnabled { zaiCard }
                }
                .padding(14)
            }
            footer
        }
        .background(Color(white: 0.115)).foregroundStyle(Color(white: 0.88)).preferredColorScheme(.dark)
        .task { store.selectedPeriod = selectedPeriod; store.refreshAll(); store.connectCursorAutomaticallyIfNeeded() }
    }

    private var summary: some View {
        let codex = store.codexForPeriod ?? store.codex
        let cursor = store.cursorForPeriod ?? store.cursor
        return UsageSummaryCard(
            metric: $metric,
            selectedPeriod: selectedPeriodBinding,
            codex: codex,
            cursor: cursor,
            codexComparison: store.codexComparison,
            cursorComparison: store.cursorComparison,
            combinedCost: store.combinedCost
        )
    }

    private var codexCard: some View {
        ProviderUsageCard(
            presentation: ProviderCardPresentationFactory.codex(
                projection: store.codex,
                quota: store.codexQuota,
                retainedQuota: store.lastPublishedCodexQuota,
                models: store.codexModelTotals,
                trend: store.codexTrend
            ),
            isExpanded: $codexDetailsExpanded
        )
    }

    private var cursorCard: some View {
        ProviderUsageCard(
            presentation: ProviderCardPresentationFactory.cursor(
                projection: store.cursor,
                quota: store.cursorQuota,
                connectionMessage: store.cursorConnectionMessage,
                isConnecting: store.isConnectingCursor,
                models: store.cursorModelTotals,
                trend: store.cursorTrend,
                lastSuccessfulRefreshAt: store.cursorLastSuccessfulRefreshAt
            ),
            isExpanded: $cursorDetailsExpanded
        )
    }

    private var claudeCard: some View {
        ProviderUsageCard(
            presentation: ProviderCardPresentationFactory.claude(
                projection: store.claude,
                models: store.claudeModelTotals,
                trend: store.claudeTrend,
                lastSuccessfulRefreshAt: store.claudeLastSuccessfulRefreshAt
            ),
            isExpanded: $claudeDetailsExpanded
        )
    }

    private var piCard: some View {
        ProviderUsageCard(
            presentation: ProviderCardPresentationFactory.pi(
                projection: store.pi,
                underlyingProviders: store.piUnderlyingProviders,
                models: store.piModelTotals,
                trend: store.piTrend,
                lastSuccessfulRefreshAt: store.piLastSuccessfulRefreshAt
            ),
            isExpanded: $piDetailsExpanded
        )
    }

    private var grokCard: some View {
        ProviderUsageCard(
            presentation: ProviderCardPresentationFactory.localExperimental(
                provider: .grok,
                plan: "xAI",
                projection: store.grok,
                message: "Local Grok session signals/transcripts. Experimental — not reconciled.",
                models: store.grokModelTotals,
                trend: store.grokTrend,
                lastSuccessfulRefreshAt: store.grokLastSuccessfulRefreshAt
            ),
            isExpanded: $grokDetailsExpanded
        )
    }

    private var zaiCard: some View {
        ProviderUsageCard(
            presentation: ProviderCardPresentationFactory.localExperimental(
                provider: .zai,
                plan: "API",
                projection: store.zai,
                message: "Z.ai model rollups via explicit Keychain credential. Experimental — not reconciled.",
                models: store.zaiModelTotals,
                trend: store.zaiTrend,
                lastSuccessfulRefreshAt: store.zaiLastSuccessfulRefreshAt
            ),
            isExpanded: $zaiDetailsExpanded
        )
    }

    private var selectedPeriod: UsageComparisonPeriod {
        UsageComparisonPeriod(rawValue: periodRawValue) ?? .today
    }

    private var selectedPeriodBinding: Binding<UsageComparisonPeriod> {
        Binding(
            get: { selectedPeriod },
            set: { period in
                periodRawValue = period.rawValue
                store.selectedPeriod = period
                store.refreshPeriod()
            }
        )
    }

    private var footer: some View {
        UsageDashboardFooter(isRefreshing: store.isImporting, lastRefreshAt: store.lastRefreshAt, onRefresh: store.refreshAll)
    }
}

#Preview { UsageDashboardView(store: AppDependencies.live().usageStore).frame(width: 360, height: 620) }
