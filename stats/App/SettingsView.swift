import SwiftUI

struct SettingsView: View {
    @Bindable var store: UsageStore
    @State private var selectedProvider: UsageProviderIdentity?
    @State private var showingDiagnostics = false
    @State private var isReturningFromDetail = false

    private let floatingHeaderHeight: CGFloat = 56

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                Group {
                    if showingDiagnostics {
                        CursorDiagnosticsView(store: store)
                            .transition(navigationTransition)
                    } else if let selectedProvider {
                        connectionDetails(selectedProvider)
                            .transition(navigationTransition)
                    } else {
                        Form {
                            Section {
                                ForEach(ProviderCatalog.enrollableProviders) { provider in
                                    connectionRow(provider: provider)
                                }
                            } header: { Text("Connections") } footer: {
                                Text("Turning a connection off pauses new refreshes. A refresh already running may finish. Saved history and credentials are kept.")
                            }
                            Section("Diagnostics") {
                                Button {
                                    withAnimation(.snappy(duration: 0.25)) {
                                        isReturningFromDetail = false
                                        showingDiagnostics = true
                                    }
                                } label: {
                                    Label("Source evidence", systemImage: "stethoscope")
                                }
                                .buttonStyle(.plain)
                                .accessibilityHint("Inspect Cursor requests and local ledger coverage")
                            }
                        }
                        .formStyle(.grouped)
                        .transition(navigationTransition)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                // Reserve space under the floating glass pill so form content is never covered.
                .safeAreaInset(edge: .top, spacing: 0) {
                    Color.clear.frame(height: floatingHeaderHeight)
                }

                header
                    .zIndex(10)
                    .allowsHitTesting(true)
            }
            .clipped()
        }
        .frame(width: 380, height: 420)
    }

    private var header: some View {
        HStack(spacing: 12) {
            if selectedProvider != nil || showingDiagnostics {
                Button {
                    withAnimation(.snappy(duration: 0.25)) {
                        isReturningFromDetail = true
                        selectedProvider = nil
                        showingDiagnostics = false
                    }
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
        .padding(.top, 8)
        .padding(.bottom, 4)
        .frame(height: floatingHeaderHeight, alignment: .top)
    }

    private var titleCapsule: some View {
        glassCapsule {
            Text(showingDiagnostics ? "Diagnostics" : selectedProvider?.name ?? "Settings")
                .font(.headline)
                .padding(.horizontal, 14)
                .frame(height: 40)
        }
    }

    private var navigationTransition: AnyTransition {
        let insertionEdge: Edge = isReturningFromDetail ? .leading : .trailing
        let removalEdge: Edge = isReturningFromDetail ? .trailing : .leading
        return .asymmetric(
            insertion: .move(edge: insertionEdge).combined(with: .opacity),
            removal: .move(edge: removalEdge).combined(with: .opacity)
        )
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
        let support = store.supportState(for: provider)
        return HStack(spacing: 12) {
        Button {
            withAnimation(.snappy(duration: 0.25)) {
                isReturningFromDetail = false
                selectedProvider = provider
            }
        } label: {
        HStack(spacing: 12) {
            ProviderBrandLogo(provider: provider, size: 20)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(provider.name).font(.body.weight(.medium))
                    ProviderSupportStateIndicator(state: support)
                }
                if let unavailable = store.unavailableMessage(for: provider), !store.isProviderEnrolled(provider) || support != .supported {
                    Text(unavailable)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else {
                    Text("\(UsageCustomizationView.metricNames(provider).count) metrics")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 12)
        }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(provider.name), \(support.accessibilityLabel)")
        .accessibilityHint(support.tooltip)
            Toggle("Enable \(provider.name) connection", isOn: connectionEnabled(provider))
                .labelsHidden()
                .toggleStyle(.switch)
                .accessibilityLabel("Enable \(provider.name) connection")
            Button {
                withAnimation(.snappy(duration: 0.25)) {
                    isReturningFromDetail = false
                    selectedProvider = provider
                }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 20, height: 28)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Configure \(provider.name)")
        }
    }

    private func connectionDetails(_ provider: UsageProviderIdentity) -> some View {
        Form {
            Section {
                HStack(spacing: 8) {
                    Text(provider.name).font(.body.weight(.medium))
                    ProviderSupportStateIndicator(state: store.supportState(for: provider))
                    Spacer()
                }
                Text(store.supportState(for: provider).tooltip)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Support")
            }

            Section("Collection & privacy") {
                Text(provider.collectionDisclosure)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section("Connection") {
                switch provider {
                case .codex: codexTrailing
                case .cursor: cursorTrailing
                case .claude: claudeTrailing
                case .pi: piTrailing
                case .grok: grokTrailing
                case .zai: zaiTrailing
                case .antigravity: antigravityTrailing
                }
                if let unavailable = store.unavailableMessage(for: provider) {
                    Text(unavailable)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
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
        Binding(
            get: { store.isProviderEnrolled(provider) },
            set: { store.setProviderEnrolled(provider, enabled: $0) }
        )
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
    private var claudeTrailing: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Local project transcripts")
            Text("Usage is read from Claude Code project JSONL files under ~/.claude/projects. No API key or account sign-in is required.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var piTrailing: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Local Pi runtime sessions")
            Text("Usage is read from Pi session JSONL under ~/.pi/agent/sessions. Underlying provider/model provenance is retained. Totals stay independent of direct provider cards.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if !store.piUnderlyingProviders.isEmpty {
                Text("Observed underlying providers: \(store.piUnderlyingProviders.joined(separator: ", "))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var grokTrailing: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Local Grok sessions")
            Text("Usage is read from local Grok session signals/transcripts under ~/.grok/sessions. No xAI API key is required for this Experimental path.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var zaiTrailing: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Explicit API credential required")
            Text("Paste a Z.ai API key to enable Experimental import. The key stays in Keychain only and is never written to the ledger, logs, diagnostics, or exports.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if ZaiCredentialVault.hasCredential() {
                HStack {
                    Text("Keychain credential present").font(.caption).foregroundStyle(.secondary)
                    Button("Remove key", role: .destructive, action: store.clearZaiAPIKey).controlSize(.small)
                }
            } else {
                Button("Use fixture credential for local testing") {
                    store.saveZaiAPIKey("fixture-zai-key-not-real")
                }
                .controlSize(.small)
            }
        }
    }

    @ViewBuilder
    private var antigravityTrailing: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Local status-line snapshots")
            Text("Usage is read from sanitized Antigravity status-line JSONL snapshots. Incomplete snapshots stay incomplete rather than fabricating totals.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
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
