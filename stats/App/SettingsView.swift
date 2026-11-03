import SwiftUI

struct SettingsView: View {
    var body: some View {
        Form {
            Section("Dashboard") {
                Text("The dashboard shows normalized local Codex token records. Sample account data is not used in the normal app.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Accounts") {
                LabeledContent("Codex", value: "Local device activity")
                LabeledContent("Cursor", value: "Not connected")
                Text("Cursor connection and account data are not part of this first implementation slice.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 420, height: 280)
    }
}
