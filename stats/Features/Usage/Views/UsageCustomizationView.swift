import SwiftUI

/// Visibility preferences only: source collection and ledger accounting are independent.
struct UsageCustomizationView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    provider(.codex)
                    provider(.cursor)
                } footer: {
                    Text("Choose which metrics appear in provider cards. Collection continues, and hidden categories remain included in totals and comparisons.")
                }
            }
            .navigationTitle("Customize metrics")
            .toolbar { Button("Done") { dismiss() } }
        }
        .frame(width: 400, height: 430)
    }

    private func provider(_ provider: UsageProviderIdentity) -> some View {
        NavigationLink {
            List {
                Section {
                    ForEach(Self.metricNames(provider), id: \.self) { name in
                        MetricVisibilityToggle(provider: provider, name: name)
                    }
                } header: {
                    Text(provider == .codex ? "Local session tokens and account quotas" : "Account token events and plan quotas")
                } footer: {
                    Text("Only metrics supported by your source are displayed. A missing value does not mean zero usage.")
                }
            }
            .navigationTitle(provider.name)
        } label: {
            HStack(spacing: 12) {
                Image(provider.logoAssetName).resizable().scaledToFit().frame(width: 22, height: 22)
                VStack(alignment: .leading) {
                    Text(provider.name)
                    Text("\(Self.metricNames(provider).count) metrics").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    static func metricNames(_ provider: UsageProviderIdentity) -> [String] {
        let quotas = provider == .codex ? ["Session", "Weekly"] : ["Total usage", "Cursor models", "Other models", "Requests"]
        let tokens = provider == .codex ? ["Input", "Cached input", "Output"] : ["Input", "Cache read", "Cache write", "Output"]
        return quotas + tokens + ["Today total", "Models", "Usage trend"]
    }
}

struct MetricVisibilityToggle: View {
    let provider: UsageProviderIdentity
    let name: String
    @AppStorage private var shown: Bool

    init(provider: UsageProviderIdentity, name: String) {
        self.provider = provider
        self.name = name
        _shown = AppStorage(wrappedValue: true, "usage.visibility.\(provider.name).\(name)")
    }

    var body: some View { Toggle(name, isOn: $shown).toggleStyle(.switch) }
}

struct VisibleUsageMetric<Content: View>: View {
    @AppStorage private var shown: Bool
    let content: Content

    init(provider: UsageProviderIdentity, name: String, @ViewBuilder content: () -> Content) {
        _shown = AppStorage(wrappedValue: true, "usage.visibility.\(provider.name).\(name)")
        self.content = content()
    }

    var body: some View {
        if shown { content }
    }
}
