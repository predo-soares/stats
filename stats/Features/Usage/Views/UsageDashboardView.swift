import SwiftUI

struct UsageDashboardView: View {
    @Bindable var store: UsageStore
    @AppStorage("usage.metric") private var metric: UsageMetric = .tokens
    @AppStorage("usage.period") private var periodRawValue: String = UsageComparisonPeriod.today.rawValue
    @State private var codexDetailsExpanded = false
    @State private var cursorDetailsExpanded = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollView { VStack(alignment: .leading, spacing: 22) { summary; codexCard; cursorCard }.padding(18) }
            footer
        }
        .background(Color(white: 0.115)).foregroundStyle(Color(white: 0.88)).preferredColorScheme(.dark)
        .task { store.selectedPeriod = selectedPeriod; store.refreshCodex(); store.refreshCursor(); store.refreshCodexQuota(); store.connectCursorAutomaticallyIfNeeded() }
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
                trend: store.cursorTrend
            ),
            isExpanded: $cursorDetailsExpanded
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
        UsageDashboardFooter(isRefreshing: store.isImporting, onRefresh: store.refreshAll)
    }
}

#Preview { UsageDashboardView(store: AppDependencies.live().usageStore).frame(width: 420, height: 720) }
