import SwiftUI

struct SettingsView: View {
    @Bindable var store: UsageStore
    @State private var selectedProvider: UsageProviderIdentity?
    @State private var showingDiagnostics = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header

                if showingDiagnostics {
                    CursorDiagnosticsView(store: store)
                } else if let selectedProvider {
                    connectionDetails(selectedProvider)
                } else {
                    Form {
                        Section {
                            connectionRow(provider: .codex)
                            connectionRow(provider: .cursor)
                        } header: { Text("Connections") } footer: {
                            Text("Turning a connection off pauses new refreshes. A refresh already running may finish. Saved history and credentials are kept.")
                        }
                        Section("Diagnostics") {
                            Button { showingDiagnostics = true } label: {
                                Label("Source evidence", systemImage: "stethoscope")
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint("Inspect Cursor requests and local ledger coverage")
                        }
                    }
                    .formStyle(.grouped)
                }
            }
        }
        .frame(width: 380, height: 420)
    }

    private var header: some View {
        HStack(spacing: 12) {
            if selectedProvider != nil || showingDiagnostics {
                Button {
                    selectedProvider = nil
                    showingDiagnostics = false
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.title3.weight(.semibold))
                        .frame(width: 32, height: 32)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .background {
                    capsuleGlass
                }
                .accessibilityLabel("Back to Settings")
            } else {
                Color.clear.frame(width: 32, height: 32)
            }

            Spacer(minLength: 0)
            titleCapsule
            Spacer(minLength: 0)

            Color.clear.frame(width: 32, height: 32)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }

    private var titleCapsule: some View {
        glassCapsule {
            Text(showingDiagnostics ? "Diagnostics" : selectedProvider?.name ?? "Settings")
                .font(.headline)
                .padding(.horizontal, 14)
                .frame(height: 40)
        }
    }

    private var capsuleGlass: some View {
        glassCapsule {
            Color.clear
                .frame(width: 40, height: 40)
        }
    }

    @ViewBuilder
    private func glassCapsule<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        if #available(macOS 26.0, *) {
            content()
                .glassEffect(.regular, in: .capsule)
        } else {
            content()
                .background(.ultraThinMaterial, in: Capsule())
        }
    }

    private func connectionRow(provider: UsageProviderIdentity) -> some View {
        HStack(spacing: 12) {
        Button { selectedProvider = provider } label: {
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
        .buttonStyle(.plain)
            Toggle("Enable \(provider.name) connection", isOn: connectionEnabled(provider))
                .labelsHidden()
                .toggleStyle(.switch)
                .accessibilityLabel("Enable \(provider.name) connection")
            Button { selectedProvider = provider } label: {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 20, height: 28)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Configure \(provider.name) metrics")
        }
    }

    private func connectionDetails(_ provider: UsageProviderIdentity) -> some View {
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
            VStack(alignment: .leading, spacing: 4) {
                Text("Local device activity")
                Text("Usage is read from Codex sessions available on this Mac.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
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
            VStack(alignment: .leading, spacing: 8) {
                LabeledContent("Workspace", value: store.cursor.workspaceName ?? "Default workspace")
                    .font(.callout)
                HStack(spacing: 8) {
                    Text("Connected")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Button("Disconnect", role: .destructive) {
                        store.disconnectCursor()
                    }
                    .controlSize(.small)
                }
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
