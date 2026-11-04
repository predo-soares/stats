import AppKit
import SwiftUI

struct UsageDashboardFooter: View {
    let isRefreshing: Bool
    let onRefresh: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Token usage").font(.caption.bold())
                Text("Local metadata only · no prompts or credentials retained")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Refresh", action: onRefresh).disabled(isRefreshing)
            Menu("Options") {
                SettingsLink { Text("Settings…") }
                Divider()
                Button("Quit", role: .destructive) { NSApplication.shared.terminate(nil) }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 13)
        .background(Color(white: 0.105))
    }
}
