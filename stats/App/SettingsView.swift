import SwiftUI

struct SettingsView: View {
    @AppStorage("stats.enableProcessTermination") private var enableProcessTermination = true

    var body: some View {
        Form {
            Toggle("Show process termination controls", isOn: $enableProcessTermination)
                .help("Hide or disable the Quit controls in CPU and memory detail panels.")

            Section("Disk Access") {
                Text("Full Disk Access cannot be requested with a normal macOS permission alert. Open System Settings to grant it manually if you want granular storage analysis.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Button("Open Full Disk Access") {
                    DiskAccessSupport.openFullDiskAccessSettings()
                }
            }
        }
        .padding(20)
        .frame(width: 360)
    }
}
