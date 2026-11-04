import SwiftUI

struct SettingsView: View {
    @Bindable var store: UsageStore

    var body: some View {
        NavigationStack {
        Form {
            Section {
                connectionRow(provider: .codex)
                connectionRow(provider: .cursor)
            } header: { Text("Connections") } footer: {
                Text("Turning a connection off pauses new refreshes. A refresh already running may finish. Saved history and credentials are kept.")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
        }
        .frame(width: 380, height: 420)
    }

    private func connectionRow(provider: UsageProviderIdentity) -> some View {
        HStack(spacing: 12) {
            Toggle("Enable \(provider.name) connection", isOn: connectionEnabled(provider))
                .labelsHidden()
                .toggleStyle(.switch)
                .accessibilityLabel("Enable \(provider.name) connection")
        NavigationLink {
            Form {
                Section("Connection") {
                    if provider == .codex { codexTrailing } else { cursorTrailing }
                }
                Section {
                    ForEach(UsageCustomizationView.metricNames(provider), id: \.self) { name in
                        MetricVisibilityToggle(provider: provider, name: name)
                    }
                } header: { Text("Metrics") } footer: {
                    Text("Choose which metrics appear in the card. Collection continues; hidden metrics remain included in totals and comparisons.")
                }
            }
            .formStyle(.grouped)
            .navigationTitle(provider.name)
        } label: {
        HStack(spacing: 12) {
            Image(provider.logoAssetName)
                .resizable()
                .scaledToFit()
                .frame(width: 20, height: 20)
            VStack(alignment: .leading, spacing: 3) {
                Text(provider.name).font(.body.weight(.medium))
                Text("\(UsageCustomizationView.metricNames(provider).count) metrics")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
        }
        }
        }
    }

    private func connectionEnabled(_ provider: UsageProviderIdentity) -> Binding<Bool> {
        provider == .codex ? $store.codexConnectionEnabled : $store.cursorConnectionEnabled
    }

    @ViewBuilder
    private var codexTrailing: some View {
        if store.needsCodexIdentityConfirmation {
            Button("Confirm") {
                store.confirmCodexAccountIdentity()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        } else {
            Text("Using the local Codex login")
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private var cursorTrailing: some View {
        if !store.pendingCursorWorkspaceScopes.isEmpty {
            Menu("Select workspace") {
                ForEach(store.pendingCursorWorkspaceScopes) { scope in
                    Button(scope.name) {
                        store.selectPendingCursorWorkspace(scope)
                    }
                }
            }
            .controlSize(.small)
        } else if store.isCursorConnected {
            HStack(spacing: 8) {
                Text("Connected")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Button("Disconnect", role: .destructive) {
                    store.disconnectCursor()
                }
                .controlSize(.small)
            }
        } else {
            Button(store.isConnectingCursor ? "Connecting…" : "Connect") {
                store.beginCursorConnection()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(store.isConnectingCursor)
        }
    }
}
