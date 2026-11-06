import SwiftUI

/// Visibility preferences only: source collection and ledger accounting are independent.
struct UsageCustomizationView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(UsageProviderIdentity.allCases) { identity in
                        providerRow(identity)
                    }
                } footer: {
                    Text("Choose which metrics appear in provider cards. Collection continues, and hidden categories remain included in totals and comparisons.")
                }
            }
            .navigationTitle("Customize metrics")
            .toolbar { Button("Done") { dismiss() } }
        }
        .frame(width: 400, height: 430)
    }

    private func providerRow(_ provider: UsageProviderIdentity) -> some View {
        NavigationLink {
            List {
                Section {
                    ForEach(Self.metricNames(provider), id: \.self) { name in
                        MetricVisibilityToggle(provider: provider, name: name)
                    }
                } header: {
                    Text(Self.providerMetricsHeader(provider))
                } footer: {
                    Text("Only metrics supported by your source are displayed. A missing value does not mean zero usage.")
                }
            }
            .navigationTitle(provider.name)
        } label: {
            HStack(spacing: 12) {
                ProviderBrandLogo(provider: provider, size: 22)
                VStack(alignment: .leading) {
                    Text(provider.name)
                    Text("\(Self.metricNames(provider).count) metrics").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    static func metricNames(_ provider: UsageProviderIdentity) -> [String] {
        let quotas: [String] = switch provider {
        case .codex: ["Session", "Weekly"]
        case .cursor: ["Total usage", "Cursor models", "Other models", "Requests"]
        case .claude, .pi, .grok, .zai: []
        }
        let tokens: [String] = switch provider {
        case .codex: ["Input", "Cached input", "Output"]
        case .cursor: ["Input", "Cache read", "Cache write", "Output"]
        case .claude: ["Input", "Cached input", "Cache creation", "Output"]
        case .pi: ["Input", "Cached input", "Cache write", "Output", "Reasoning"]
        case .grok: ["Input", "Cached input", "Cache creation", "Output", "Reasoning"]
        case .zai: ["Input", "Cached input", "Output", "Reasoning"]
        }
        return quotas + tokens + ["Today total", "Models", "Usage trend"]
    }

    private static func providerMetricsHeader(_ provider: UsageProviderIdentity) -> String {
        switch provider {
        case .codex: "Local session tokens and account quotas"
        case .cursor: "Account token events and plan quotas"
        case .claude: "Local Claude Code token categories"
        case .pi: "Local Pi runtime token categories with provenance"
        case .grok: "Local Grok session token categories"
        case .zai: "Z.ai model usage rollups"
        }
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
