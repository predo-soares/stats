import AppKit
import Charts
import SwiftUI

struct UsageDashboardView: View {
    @Bindable var store: UsageStore
    @AppStorage("usage.metric") private var metric: UsageMetric = .tokens
    @AppStorage("usage.period") private var periodRawValue: String = UsageComparisonPeriod.today.rawValue
    @State private var codexDetailsExpanded = false
    @State private var cursorDetailsExpanded = false
    @State private var codexCardHovered = false
    @State private var cursorCardHovered = false
    private let cardColor = Color(white: 0.14)

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
        let projection = store.codex
        return VStack(alignment: .leading, spacing: 14) {
            ProviderIdentityHeader(provider: .codex, plan: "Plus", trailingLabel: "Local device activity")
            quotaSection
            if codexDetailsExpanded {
                VStack(alignment: .leading, spacing: 6) {
                tokenRow("Input", projection.inputTokens); tokenRow("Cached input", projection.cachedInputTokens); tokenRow("Output", projection.outputTokens)
                Divider().overlay(.white.opacity(0.1))
                totalRow(projection.totalTokens)
                providerDetails(models: store.codexModelTotals, trend: store.codexTrend)
                statusLine
                }
            }
        }
        .padding(18)
        .background(cardColor, in: RoundedRectangle(cornerRadius: 18))
        .overlay(alignment: .bottom) { viewMoreOverlay(visible: codexCardHovered && !codexDetailsExpanded) }
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .contentShape(RoundedRectangle(cornerRadius: 18))
        .onHover { codexCardHovered = $0 }
        .onTapGesture { codexDetailsExpanded.toggle() }
    }

    @ViewBuilder private var quotaSection: some View {
        switch store.codexQuota {
        case .published(let snapshot):
            ForEach(snapshot.windows) { window in
                UsageQuotaWindow(name: window.name, remainingFraction: window.remainingFraction, resetsAt: window.resetsAt)
            }
        case .authenticationMissing: Text("Codex quota unavailable until Codex authentication can be read.").font(.caption).foregroundStyle(.secondary)
        case .authenticationExpired: Text("Renew authentication in Codex, then refresh.").font(.caption).foregroundStyle(.orange)
        case .awaitingIdentityConfirmation(_, let pending): Text("Confirm new Codex account: \(pending)").font(.caption).foregroundStyle(.orange)
        case .unavailable(let message, _): Text(message).font(.caption).foregroundStyle(.red)
        }
    }

    private func tokenRow(_ name: String, _ tokens: Int) -> some View {
        HStack(spacing: 12) { Text(name).foregroundStyle(.secondary).lineLimit(1).layoutPriority(1); Spacer(minLength: 8); Text(UsageMetric.tokens.formatted(tokens)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.8).fixedSize(horizontal: true, vertical: false) }.font(.system(size: 13, weight: .medium))
    }

    private func totalRow(_ value: Int) -> some View {
        HStack(spacing: 12) { Text("Today total").font(.headline).lineLimit(1); Spacer(minLength: 8); Text(UsageMetric.tokens.formatted(value)).font(.headline).monospacedDigit().lineLimit(1).minimumScaleFactor(0.8).fixedSize(horizontal: true, vertical: false) }
    }

    @ViewBuilder private var statusLine: some View {
        switch store.codex.coverage {
        case .accessError(let message): Text(message).font(.caption).foregroundStyle(.red)
        case .importing: ProgressView("Importing available local sessions…").font(.caption)
        case .empty: Text("No token records were found. This does not establish complete history.").font(.caption).foregroundStyle(.secondary)
        case .available: Text("Observation cutoff: \(store.codex.cutoff?.formatted(date: .omitted, time: .shortened) ?? "unknown") · \(store.codex.records) normalized records").font(.caption).foregroundStyle(.secondary)
        }
    }

    private var cursorCard: some View {
        let projection = store.cursor
        return VStack(alignment: .leading, spacing: 10) {
            ProviderIdentityHeader(provider: .cursor, plan: "Premium")
            if store.cursor.workspaceName == nil {
                Text(store.isConnectingCursor ? "Opening Cursor sign-in in your browser…" : "Cursor sign-in starts automatically when this panel opens.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let message = store.cursorConnectionMessage { Text(message).font(.caption).foregroundStyle(.secondary) }
            cursorQuotaSection
            if cursorDetailsExpanded {
                VStack(alignment: .leading, spacing: 6) {
                tokenRow("Input", projection.inputTokens); tokenRow("Cache read", projection.cacheReadTokens); tokenRow("Cache write", projection.cacheWriteTokens); tokenRow("Output", projection.outputTokens)
                totalRow(projection.totalTokens)
                providerDetails(models: store.cursorModelTotals, trend: store.cursorTrend)
                switch store.cursor.coverage { case .unavailable(let message): Text(message).font(.caption).foregroundStyle(.red); default: Text(store.cursor.coverage.label).font(.caption).foregroundStyle(.secondary) }
                }
            }
        }
            .padding(18)
            .background(cardColor, in: RoundedRectangle(cornerRadius: 18))
            .overlay(alignment: .bottom) { viewMoreOverlay(visible: cursorCardHovered && !cursorDetailsExpanded) }
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .contentShape(RoundedRectangle(cornerRadius: 18))
            .onHover { cursorCardHovered = $0 }
            .onTapGesture { cursorDetailsExpanded.toggle() }
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

    @ViewBuilder private func providerDetails(models: [UsageModelTotal], trend: [UsageTrendBucket]) -> some View {
        if !models.isEmpty {
            DisclosureGroup("Models") {
                ForEach(models.prefix(5)) { model in
                    HStack {
                        Text(model.model).lineLimit(1).foregroundStyle(.secondary)
                        Spacer()
                        Text(UsageMetric.tokens.formatted(model.totalTokens)).monospacedDigit()
                    }.font(.caption)
                }
            }.font(.caption.bold())
        }
        if !trend.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text("Usage trend").font(.caption.bold())
                Chart(trend) { bucket in
                    BarMark(x: .value("Time", bucket.start), y: .value("Tokens", bucket.totalTokens))
                        .foregroundStyle(.blue)
                }
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .frame(height: 42)
            }
        }
    }

    @ViewBuilder private var cursorQuotaSection: some View {
        switch store.cursorQuota {
        case .published(let windows):
            ForEach(windows) { window in
                UsageQuotaWindow(name: window.name, remainingFraction: window.remainingFraction, resetsAt: window.resetsAt)
            }
        case .unavailable(let message):
            Text(message).font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private func viewMoreOverlay(visible: Bool) -> some View {
        if visible {
            ZStack(alignment: .bottom) {
                LinearGradient(colors: [.clear, cardColor], startPoint: .top, endPoint: .bottom)
                    .frame(height: 42)
                Text("View more")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 10)
            }
            .frame(height: 42)
            .allowsHitTesting(false)
        }
    }

    private var footer: some View {
        UsageDashboardFooter(isRefreshing: store.isImporting, onRefresh: store.refreshAll)
    }
}

#Preview { UsageDashboardView(store: AppDependencies.live().usageStore).frame(width: 420, height: 720) }
