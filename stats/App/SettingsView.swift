import SwiftUI

struct SettingsView: View {
    @AppStorage("stats.enableProcessTermination") private var enableProcessTermination = true

    var body: some View {
        Form {
            Toggle("Show process termination controls", isOn: $enableProcessTermination)
                .help("Hide or disable the Quit controls in CPU and memory detail panels.")

            Section("Device Permissions") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Granular Storage Access")
                        .font(.headline.weight(.semibold))

                    Text("Category and file-level storage analysis may require folder permissions or Full Disk Access. macOS does not show a normal permission prompt for Full Disk Access, so you need to enable it in System Settings.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("Desktop, Documents, and Downloads can still use standard macOS folder prompts when the app accesses them.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button("Open Full Disk Access") {
                    DiskAccessSupport.openFullDiskAccessSettings()
                }
            }
        }
        .padding(20)
        .frame(width: 420)
    }
}
