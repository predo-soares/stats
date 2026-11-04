import SwiftUI

struct SettingsView: View {
    @Bindable var store: UsageStore

    var body: some View {
        Form {
            Section("Dashboard") {
                Text("The dashboard shows local Codex token records and connected Cursor account activity. Sample account data is not used in the normal app.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Codex") {
                LabeledContent("Source", value: store.codexAccountSummary)
                Text("Codex credentials stay in Codex. This app only reads local session metadata and quota.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Cursor") {
                LabeledContent("Account", value: store.cursorAccountSummary)
                if !store.pendingCursorWorkspaceScopes.isEmpty {
                    Text("Select one workspace. Histories stay separate per scope.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ForEach(store.pendingCursorWorkspaceScopes) { scope in
                        Button(scope.name) {
                            store.selectPendingCursorWorkspace(scope)
                        }
                    }
                } else if store.isCursorConnected {
                    Button("Disconnect Cursor", role: .destructive) {
                        store.disconnectCursor()
                    }
                } else {
                    Button(store.isConnectingCursor ? "Waiting for browser…" : "Connect Cursor…") {
                        store.beginCursorConnection()
                    }
                    .disabled(store.isConnectingCursor)
                }
                if let message = store.cursorConnectionMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 420, height: 360)
    }
}
