import AppKit
import Charts
import SwiftUI

struct UsageDashboardView: View {
    @Bindable var store: UsageStore
    @AppStorage("usage.metric") private var metric: UsageMetric = .tokens
    @AppStorage("usage.period") private var periodRawValue: String = UsageComparisonPeriod.today.rawValue
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
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Picker("Metric", selection: $metric) { ForEach(UsageMetric.allCases) { Text($0.rawValue).tag($0) } }
                    .pickerStyle(.menu).frame(width: 160)
                Spacer()
                Button("Refresh") { store.refreshCodex() }.disabled(store.isImporting)
            }.font(.system(size: 18, weight: .semibold))
            Picker("Period", selection: Binding(get: { selectedPeriod }, set: { period in periodRawValue = period.rawValue; store.selectedPeriod = period; store.refreshPeriod() })) {
                ForEach(UsageComparisonPeriod.allCases) { period in Text(period.title).tag(period) }
            }.pickerStyle(.segmented)
            if metric == .cost { unavailableMetricMessage }
            HStack(spacing: 20) {
                Chart { SectorMark(angle: .value("Codex", codex.totalTokens), innerRadius: .ratio(0.67)).foregroundStyle(.green); SectorMark(angle: .value("Cursor", cursor.totalTokens), innerRadius: .ratio(0.67)).foregroundStyle(.blue) }
                    .chartLegend(.hidden)
                    .chartBackground { _ in VStack(spacing: 2) { Text(UsageMetric.tokens.formatted(total)).font(.title2.bold()).monospacedDigit().lineLimit(1).minimumScaleFactor(0.75); Text(selectedPeriod.title).font(.caption).foregroundStyle(.secondary) } }
                    .frame(width: 132, height: 132)
                    .accessibilityLabel("Combined token consumption today")
                    .accessibilityValue(UsageMetric.tokens.formatted(total))
                VStack(alignment: .leading, spacing: 8) {
                    Label(selectedPeriod.title, systemImage: "chart.pie").font(.headline)
                    Text(UsageMetric.tokens.formatted(total)).font(.title3.bold()).monospacedDigit().lineLimit(1).minimumScaleFactor(0.8)
                    comparisonLabel(store.combinedComparison, prefix: "Combined")
                }; Spacer()
            }.padding(16).background(cardColor, in: RoundedRectangle(cornerRadius: 18))
        }
    }

    private var codexCard: some View {
        let projection = store.codex
        return VStack(alignment: .leading, spacing: 14) {
            HStack { Label("Codex", systemImage: "command").font(.title3.bold()); Spacer(); Text("Local device activity").font(.caption).foregroundStyle(.secondary) }
            tokenRow("Input", projection.inputTokens); tokenRow("Cached input", projection.cachedInputTokens); tokenRow("Output", projection.outputTokens)
            Divider().overlay(.white.opacity(0.1))
            totalRow(projection.totalTokens)
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
            HStack { Label("Cursor", systemImage: "cube.fill").font(.title3.bold()); Spacer(); Button("Refresh") { store.refreshCursor() } }
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
            switch store.cursor.coverage { case .unavailable(let message): Text(message).font(.caption).foregroundStyle(.red); default: Text(store.cursor.coverage.label).font(.caption).foregroundStyle(.secondary) }
        }
            .padding(18).background(cardColor, in: RoundedRectangle(cornerRadius: 18))
    }

    private var selectedPeriod: UsageComparisonPeriod {
        UsageComparisonPeriod(rawValue: periodRawValue) ?? .today
    }

    private var unavailableMetricMessage: some View {
        Text("Estimated Cost is not available until model-level historical pricing is connected.")
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    @ViewBuilder private func comparisonLabel(_ comparison: UsageTokenComparison, prefix: String) -> some View {
        switch comparison.outcome {
        case .percentage(let value): Text("\(prefix): \(value >= 0 ? "↑" : "↓") \(abs(value), specifier: "%.0f")% vs previous period").font(.caption).foregroundStyle(.secondary)
        case .noPreviousUsage: Text("\(prefix): No previous usage").font(.caption).foregroundStyle(.secondary)
        case .noChange: Text("\(prefix): No change vs previous period").font(.caption).foregroundStyle(.secondary)
        case .unavailable: if let label = comparison.coverage.label { Text(label).font(.caption).foregroundStyle(.secondary) }
        }
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
        HStack { VStack(alignment: .leading, spacing: 2) { Text("Token usage").font(.caption.bold()); Text("Local metadata only · no prompts or credentials retained").font(.caption2).foregroundStyle(.secondary) }; Spacer(); Menu("Options") { SettingsLink { Text("Settings…") }; Divider(); Button("Quit", role: .destructive) { NSApplication.shared.terminate(nil) } } }
            .padding(.horizontal, 18).padding(.vertical, 13).background(Color(white: 0.105))
    }
}

#Preview { UsageDashboardView(store: UsageStore()).frame(width: 420, height: 720) }
