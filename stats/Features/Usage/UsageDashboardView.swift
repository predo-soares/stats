import AppKit
import Charts
import SwiftUI

struct UsageDashboardView: View {
    @Bindable var store: UsageStore
    @AppStorage("usage.metric") private var metric: UsageMetric = .tokens
    @AppStorage("usage.period") private var periodRawValue: String = UsageComparisonPeriod.today.rawValue
    @State private var metricMenuHovered = false
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
            Picker("Period", selection: Binding(get: { selectedPeriod }, set: { period in periodRawValue = period.rawValue; store.selectedPeriod = period; store.refreshPeriod() })) {
                ForEach(UsageComparisonPeriod.allCases) { period in Text(period.title).tag(period) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: .infinity)
        }
        .padding(16)
        .background(cardColor, in: RoundedRectangle(cornerRadius: 18))
    }

    private var codexCard: some View {
        let projection = store.codex
        return VStack(alignment: .leading, spacing: 14) {
            HStack { providerLabel("Codex"); Spacer(); Text("Local device activity").font(.caption).foregroundStyle(.secondary) }
            tokenRow("Input", projection.inputTokens); tokenRow("Cached input", projection.cachedInputTokens); tokenRow("Output", projection.outputTokens)
            Divider().overlay(.white.opacity(0.1))
            totalRow(projection.totalTokens)
            providerDetails(models: store.codexModelTotals, trend: store.codexTrend)
            quotaSection
            statusLine
        }.padding(18).background(cardColor, in: RoundedRectangle(cornerRadius: 18))
    }

    @ViewBuilder private var quotaSection: some View {
        switch store.codexQuota {
        case .published(let snapshot):
            ForEach(snapshot.windows) { window in
                HStack(spacing: 8) { Text(window.name).foregroundStyle(.secondary).lineLimit(1).layoutPriority(1); Spacer(minLength: 8); Text("\(Int((window.remainingFraction * 100).rounded()))% left").monospacedDigit().fixedSize(); if let reset = window.resetsAt { Text(reset.formatted(date: .omitted, time: .shortened)).foregroundStyle(.secondary).fixedSize() } }.font(.caption)
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
            HStack { providerLabel("Cursor"); Spacer(); Button("Refresh") { store.refreshCursor() } }
            if store.cursor.workspaceName == nil {
                Text(store.isConnectingCursor ? "Opening Cursor sign-in in your browser…" : "Cursor sign-in starts automatically when this panel opens.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let message = store.cursorConnectionMessage { Text(message).font(.caption).foregroundStyle(.secondary) }
            if let workspace = store.cursor.workspaceName { Text(workspace).font(.caption).foregroundStyle(.secondary) }
            cursorQuotaSection
            tokenRow("Input", projection.inputTokens); tokenRow("Cache read", projection.cacheReadTokens); tokenRow("Cache write", projection.cacheWriteTokens); tokenRow("Output", projection.outputTokens)
            totalRow(projection.totalTokens)
            providerDetails(models: store.cursorModelTotals, trend: store.cursorTrend)
            switch store.cursor.coverage { case .unavailable(let message): Text(message).font(.caption).foregroundStyle(.red); default: Text(store.cursor.coverage.label).font(.caption).foregroundStyle(.secondary) }
        }
            .padding(18).background(cardColor, in: RoundedRectangle(cornerRadius: 18))
    }

    private var selectedPeriod: UsageComparisonPeriod {
        UsageComparisonPeriod(rawValue: periodRawValue) ?? .today
    }

    private func legendItem(_ label: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label).font(.caption).foregroundStyle(.secondary)
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

    private func providerLabel(_ name: String) -> some View {
        HStack(spacing: 8) {
            Image(name == "Codex" ? "CodexLogo" : "CursorLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 18, height: 18)
            Text(name).font(.title3.bold())
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
        let color: Color = muted ? .secondary.opacity(0.5) : value > 0 ? .orange : value < 0 ? .green : .secondary
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
            ForEach(windows) { window in
                HStack(spacing: 8) {
                    Text(window.name).foregroundStyle(.secondary).lineLimit(1).layoutPriority(1)
                    Spacer(minLength: 8)
                    Text("\(Int((window.remainingFraction * 100).rounded()))% left").monospacedDigit().fixedSize()
                    if let reset = window.resetsAt { Text("Resets \(reset.formatted(date: .omitted, time: .shortened))").foregroundStyle(.secondary).fixedSize() }
                }.font(.caption)
            }
        case .unavailable(let message):
            Text(message).font(.caption).foregroundStyle(.secondary)
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
