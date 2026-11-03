import AppKit
import Charts
import SwiftUI

struct UsageDashboardView: View {
    @Bindable var store: UsageStore
    @AppStorage("usage.metric") private var metric: UsageMetric = .tokens
    private let cardColor = Color(white: 0.14)

    var body: some View {
        VStack(spacing: 0) {
            ScrollView { VStack(alignment: .leading, spacing: 22) { summary; codexCard; cursorCard }.padding(18) }
            footer
        }
        .background(Color(white: 0.115)).foregroundStyle(Color(white: 0.88)).preferredColorScheme(.dark)
        .task { store.refreshCodex() }
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Picker("Metric", selection: $metric) { ForEach(UsageMetric.allCases) { Text($0.rawValue).tag($0) } }
                    .pickerStyle(.menu).frame(width: 160)
                Spacer()
                Button("Refresh") { store.refreshCodex() }.disabled(store.isImporting)
            }.font(.system(size: 18, weight: .semibold))
            HStack(spacing: 20) {
                Chart { SectorMark(angle: .value("Tokens", store.codex.totalTokens), innerRadius: .ratio(0.67)).foregroundStyle(.green) }
                    .chartLegend(.hidden)
                    .chartBackground { _ in VStack(spacing: 2) { Text(UsageMetric.tokens.formatted(store.codex.totalTokens)).font(.title2.bold()).monospacedDigit(); Text("tokens").font(.caption).foregroundStyle(.secondary) } }
                    .frame(width: 132, height: 132)
                    .accessibilityLabel("Codex token consumption today")
                    .accessibilityValue(UsageMetric.tokens.formatted(store.codex.totalTokens))
                VStack(alignment: .leading, spacing: 8) {
                    Label("Codex", systemImage: "command").font(.headline)
                    Text(UsageMetric.tokens.formatted(store.codex.totalTokens)).font(.title3.bold()).monospacedDigit()
                    Text("Today · \(store.codex.coverage.label)").font(.caption).foregroundStyle(.secondary)
                }; Spacer()
            }.padding(16).background(cardColor, in: RoundedRectangle(cornerRadius: 18))
        }
    }

    private var codexCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack { Label("Codex", systemImage: "command").font(.title3.bold()); Spacer(); Text("Local device activity").font(.caption).foregroundStyle(.secondary) }
            tokenRow("Input", store.codex.inputTokens); tokenRow("Cached input", store.codex.cachedInputTokens); tokenRow("Output", store.codex.outputTokens)
            Divider().overlay(.white.opacity(0.1))
            HStack { Text("Today total").font(.headline); Spacer(); Text(UsageMetric.tokens.formatted(store.codex.totalTokens)).font(.headline).monospacedDigit() }
            statusLine
        }.padding(18).background(cardColor, in: RoundedRectangle(cornerRadius: 18))
    }

    private func tokenRow(_ name: String, _ tokens: Int) -> some View {
        HStack { Text(name).foregroundStyle(.secondary); Spacer(); Text(UsageMetric.tokens.formatted(tokens)).monospacedDigit() }.font(.system(size: 13, weight: .medium))
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
        VStack(alignment: .leading, spacing: 8) { Label("Cursor", systemImage: "cube.fill").font(.title3.bold()); Text("Not connected. Connect Cursor in the next approved slice.").font(.caption).foregroundStyle(.secondary) }
            .padding(18).background(cardColor, in: RoundedRectangle(cornerRadius: 18))
    }

    private var footer: some View {
        HStack { VStack(alignment: .leading, spacing: 2) { Text("Token usage").font(.caption.bold()); Text("Local metadata only · no prompts or credentials retained").font(.caption2).foregroundStyle(.secondary) }; Spacer(); Menu("Options") { SettingsLink { Text("Settings…") }; Divider(); Button("Quit", role: .destructive) { NSApplication.shared.terminate(nil) } } }
            .padding(.horizontal, 18).padding(.vertical, 13).background(Color(white: 0.105))
    }
}

#Preview { UsageDashboardView(store: UsageStore()).frame(width: 420, height: 720) }
