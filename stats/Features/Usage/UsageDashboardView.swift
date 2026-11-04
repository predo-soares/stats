import AppKit
import Charts
import SwiftUI

struct UsageDashboardView: View {
    @Bindable var store: UsageStore
    @AppStorage("usage.metric") private var metric: UsageMetric = .tokens
    @AppStorage("usage.period") private var periodRawValue: String = UsageComparisonPeriod.today.rawValue
    @State private var metricMenuHovered = false
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
        let total = codex.totalTokens + cursor.totalTokens
        let cost = store.combinedCost
        return VStack(alignment: .leading, spacing: 16) {
            HStack {
                Menu {
                    ForEach(UsageMetric.allCases) { option in
                        Button(option.rawValue) { metric = option }
                    }
                } label: {
                    HStack(spacing: 5) {
                        Text(metric.rawValue)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption2.weight(.semibold))
                    }
                    .padding(.vertical, 3)
                    .padding(.horizontal, 5)
                    .background(metricMenuHovered ? Color.white.opacity(0.1) : .clear, in: RoundedRectangle(cornerRadius: 6))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .onHover { metricMenuHovered = $0 }
                Spacer()
            }.font(.system(size: 18, weight: .semibold))
            if metric == .cost, let cost { costStatus(cost) }
            HStack(spacing: 20) {
                if metric == .tokens {
                    Chart { SectorMark(angle: .value("Codex", codex.totalTokens), innerRadius: .ratio(0.67)).foregroundStyle(.green); SectorMark(angle: .value("Cursor", cursor.totalTokens), innerRadius: .ratio(0.67)).foregroundStyle(.blue) }
                        .chartLegend(.hidden)
                        .chartBackground { _ in VStack(spacing: 2) { Text(UsageMetric.tokens.formatted(total)).font(.title2.bold()).monospacedDigit().lineLimit(1).minimumScaleFactor(0.75); Text(selectedPeriod.title).font(.caption).foregroundStyle(.secondary) } }
                        .frame(width: 132, height: 132)
                        .accessibilityLabel("Combined token consumption")
                        .accessibilityValue(UsageMetric.tokens.formatted(total))
                } else {
                    RoundedRectangle(cornerRadius: 66).fill(cardColor).frame(width: 132, height: 132)
                        .overlay { Text(formattedCost(cost)).font(.title3.bold()).monospacedDigit().minimumScaleFactor(0.6) }
                        .accessibilityLabel("Combined estimated cost")
                }
                VStack(alignment: .leading, spacing: 8) {
                    summaryLegendRow("Codex", color: .green, comparison: store.codexComparison)
                    summaryLegendRow("Cursor", color: .blue, comparison: store.cursorComparison)
                }; Spacer()
            }
            UsagePeriodPicker(selection: Binding(get: { selectedPeriod }, set: { period in periodRawValue = period.rawValue; store.selectedPeriod = period; store.refreshPeriod() }))
                .frame(maxWidth: .infinity)
        }
        .padding(16)
        .background(cardColor, in: RoundedRectangle(cornerRadius: 18))
    }

    private var codexCard: some View {
        let projection = store.codex
        return VStack(alignment: .leading, spacing: 14) {
            HStack { providerLabel("Codex", plan: "Plus"); Spacer(); Text("Local device activity").font(.caption).foregroundStyle(.secondary) }
            quotaSection
            if codexDetailsExpanded {
                VStack(alignment: .leading, spacing: 10) {
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
            ForEach(snapshot.windows) { window in quotaWindowRow(window.name, remaining: window.remainingFraction, reset: window.resetsAt) }
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
            HStack { providerLabel("Cursor", plan: "Premium"); Spacer() }
            if store.cursor.workspaceName == nil {
                Text(store.isConnectingCursor ? "Opening Cursor sign-in in your browser…" : "Cursor sign-in starts automatically when this panel opens.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let message = store.cursorConnectionMessage { Text(message).font(.caption).foregroundStyle(.secondary) }
            if let workspace = store.cursor.workspaceName { Text(workspace).font(.caption).foregroundStyle(.secondary) }
            cursorQuotaSection
            if cursorDetailsExpanded {
                VStack(alignment: .leading, spacing: 10) {
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

    private func legendItem(_ label: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 9, height: 9)
            Text(label).font(.subheadline.weight(.medium)).foregroundStyle(.primary)
        }
    }

    @ViewBuilder private func summaryLegendRow(_ label: String, color: Color, comparison: UsageTokenComparison) -> some View {
        HStack(spacing: 10) {
            legendItem(label, color: color)
            if metric == .tokens {
                comparisonIndicator(comparison)
            } else {
                comparisonDeltaIcon(value: 0, text: "--", muted: true)
            }
        }
    }

    private func providerLabel(_ name: String, plan: String) -> some View {
        HStack(spacing: 8) {
            Image(name == "Codex" ? "CodexLogo" : "CursorLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 18, height: 18)
            Text(name).font(.title3.bold())
            Text(plan).font(.title3.weight(.medium)).foregroundStyle(.secondary)
        }
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

    @ViewBuilder private func costStatus(_ result: UsageCostResult) -> some View {
        if result.isComplete {
            Text("Estimated Cost · pricing \(result.catalogRevision)").font(.caption).foregroundStyle(.secondary)
        } else {
            Text("Incomplete estimate · unknown models: " + result.estimate.unpricedModels.joined(separator: ", ")).font(.caption).foregroundStyle(.orange).lineLimit(2)
        }
    }

    private func formattedCost(_ result: UsageCostResult?) -> String {
        guard let result else { return "—" }
        if result.usageRecords > 0, result.estimate.pricedTokens == 0 { return "—" }
        return UsageMetric.cost.formattedCost(result.estimate.pricedCost)
    }

    @ViewBuilder private func comparisonIndicator(_ comparison: UsageTokenComparison) -> some View {
        switch comparison.outcome {
        case .percentage(let value): comparisonDeltaIcon(value: value, text: String(format: "%.0f%%", abs(value)), muted: false)
        case .noPreviousUsage: comparisonDeltaIcon(value: 1, text: "--", muted: true)
        case .noChange: comparisonDeltaIcon(value: 0, text: "0%", muted: false)
        case .unavailable: comparisonDeltaIcon(value: 0, text: "--", muted: true)
        }
    }

    @ViewBuilder private func costComparisonIndicator(_ comparison: UsageCostComparison) -> some View {
        switch comparison.outcome {
        case .percentage(let value): comparisonDeltaIcon(value: value, text: String(format: "%.0f%%", abs(value)), muted: false)
        case .noPreviousCost: comparisonDeltaIcon(value: 1, text: "--", muted: true)
        case .noChange: comparisonDeltaIcon(value: 0, text: "0%", muted: false)
        case .unavailable: comparisonDeltaIcon(value: 0, text: "--", muted: true)
        }
    }

    private func comparisonDeltaIcon(value: Double, text: String, muted: Bool) -> some View {
        let color: Color = muted ? .secondary.opacity(0.5) : value > 0 ? .green : value < 0 ? .red : .secondary
        return HStack(spacing: 4) {
            Image(systemName: value > 0 ? "arrow.up.right" : value < 0 ? "arrow.down.right" : "arrow.up.arrow.down")
            Text(text).monospacedDigit()
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(color)
    }

    @ViewBuilder private var cursorQuotaSection: some View {
        switch store.cursorQuota {
        case .published(let windows):
            ForEach(windows) { window in quotaWindowRow(window.name, remaining: window.remainingFraction, reset: window.resetsAt) }
        case .unavailable(let message):
            Text(message).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func quotaWindowRow(_ name: String, remaining: Double, reset: Date?) -> some View {
        let percent = Int((remaining * 100).rounded())
        let fill = remaining <= 0.2 ? Color.red : Color.accentColor
        return VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(name).font(.headline)
                Spacer()
            }
            ProgressView(value: min(max(remaining, 0), 1))
                .progressViewStyle(.linear)
                .tint(fill)
            HStack {
                Text("\(percent)% left").font(.subheadline.weight(.semibold)).monospacedDigit()
                Spacer()
                if let reset { Text("Resets \(reset.formatted(date: .abbreviated, time: .shortened))").font(.subheadline).foregroundStyle(.secondary) }
            }
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
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Token usage").font(.caption.bold())
                Text("Local metadata only · no prompts or credentials retained").font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Refresh") { store.refreshAll() }.disabled(store.isImporting)
            Menu("Options") { SettingsLink { Text("Settings…") }; Divider(); Button("Quit", role: .destructive) { NSApplication.shared.terminate(nil) } }
        }
            .padding(.horizontal, 18).padding(.vertical, 13).background(Color(white: 0.105))
    }
}

#Preview { UsageDashboardView(store: UsageStore()).frame(width: 420, height: 720) }

private struct UsagePeriodPicker: View {
    @Binding var selection: UsageComparisonPeriod
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            let count = CGFloat(UsageComparisonPeriod.allCases.count)
            let slotWidth = proxy.size.width / count
            let index = CGFloat(UsageComparisonPeriod.allCases.firstIndex(of: selection) ?? 0)
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.07))
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.accentColor)
                    .frame(width: max(0, slotWidth - 6), height: max(0, proxy.size.height - 6))
                    .offset(x: index * slotWidth + 3)
                    .animation(reduceMotion ? .linear(duration: 0.01) : .spring(response: 0.32, dampingFraction: 0.82), value: selection)
                HStack(spacing: 0) {
                    ForEach(UsageComparisonPeriod.allCases) { period in
                        Button {
                            withAnimation(reduceMotion ? .linear(duration: 0.01) : .spring(response: 0.32, dampingFraction: 0.82)) { selection = period }
                        } label: {
                            Text(period.title)
                                .font(.caption.weight(.semibold))
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(selection == period ? Color.primary : Color.secondary)
                        .accessibilityAddTraits(selection == period ? .isSelected : [])
                    }
                }
            }
        }
        .frame(height: 32)
    }
}
