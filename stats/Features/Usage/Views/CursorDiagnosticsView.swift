import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct CursorDiagnosticsView: View {
    @Bindable var store: UsageStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Cursor Source Evidence")
                    .font(.title3.weight(.semibold))
                Text("This report contains local accounting metadata only. Credentials, prompts, source code, and raw API payloads are excluded.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if store.isLoadingCursorSourceEvidence {
                    ProgressView("Reading local ledger…")
                } else if let evidence = store.cursorSourceEvidence {
                    LabeledContent("Connected account", value: evidence.accountFingerprint)
                        .font(.callout)
                    probeCard(evidence.currentProbe)
                    ForEach(evidence.windows) { window in
                        windowCard(window)
                    }
                    importRanges(evidence.importRanges)
                    HStack {
                        Button("Run check") { store.loadCursorSourceEvidence() }
                        Button("Export redacted JSON") { export(evidence) }
                    }
                    .buttonStyle(.bordered)
                } else {
                    Text(store.cursorSourceEvidenceError ?? "No source evidence has been loaded.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Button("Run check") { store.loadCursorSourceEvidence() }
                        .buttonStyle(.borderedProminent)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 64)
            .padding(.bottom, 20)
        }
        .task { store.loadCursorSourceEvidence() }
    }

    private func windowCard(_ window: CursorEvidenceWindow) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(window.label).font(.headline)
                Spacer()
                Text(window.coverage).font(.caption).foregroundStyle(.secondary)
            }
            LabeledContent("Requested", value: "\(window.requestedStart.formatted(date: .abbreviated, time: .shortened)) – \(window.requestedEnd.formatted(date: .abbreviated, time: .shortened))")
            LabeledContent("Response events", value: window.eventCount.formatted())
            LabeledContent("Token subtotal", value: UsageMetric.tokens.formatted(window.tokenSubtotal))
            LabeledContent("Earliest event", value: window.earliestEvent?.formatted(date: .abbreviated, time: .shortened) ?? "—")
            LabeledContent("Latest event", value: window.latestEvent?.formatted(date: .abbreviated, time: .shortened) ?? "—")
        }
        .font(.caption)
        .padding(12)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
    }

    private func probeCard(_ probe: CursorSourceProbe) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Live Today probe").font(.headline)
            LabeledContent("Outcome", value: probe.outcome)
            LabeledContent("Response events", value: probe.eventCount.formatted())
            LabeledContent("Token subtotal", value: UsageMetric.tokens.formatted(probe.tokenSubtotal))
            LabeledContent("Latest event", value: probe.latestEvent?.formatted(date: .abbreviated, time: .shortened) ?? "—")
            if let message = probe.message { Text(message).foregroundStyle(.secondary) }
        }
        .font(.caption)
        .padding(12)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
    }

    private func importRanges(_ ranges: [CursorEvidenceImportRange]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Import ranges").font(.headline)
            if ranges.isEmpty {
                Text("No Cursor requests have been retained.").foregroundStyle(.secondary)
            } else {
                ForEach(ranges) { range in
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(range.requestedStart.formatted(date: .abbreviated, time: .omitted)) – \(range.requestedEnd.formatted(date: .abbreviated, time: .shortened))")
                        Text(range.state.capitalized + (range.message.map { ": \($0)" } ?? ""))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .font(.caption)
    }

    private func export(_ evidence: CursorSourceEvidence) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "cursor-source-evidence.json"
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? encoder.encode(evidence).write(to: url, options: .atomic)
    }
}
