import AppKit
import SwiftUI

struct UsageDashboardFooter: View {
    let isRefreshing: Bool
    let lastRefreshAt: Date?
    let onRefresh: () -> Void
    @State private var isRefreshHovered = false

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Token usage").font(.caption.bold())
                Button(action: onRefresh) {
                    TimelineView(.periodic(from: .now, by: 60)) { context in
                        HStack(spacing: 0) {
                            Text("Last search ")
                            if let lastRefreshAt {
                                Text("\(elapsedMinutes(since: lastRefreshAt, now: context.date))m ago")
                            } else {
                                Text("not yet")
                            }
                            Text(" · ⌘R to refresh")
                        }
                        .font(.caption2)
                        .foregroundStyle(isRefreshHovered ? .primary : .secondary)
                    }
                }
                .buttonStyle(.plain)
                .disabled(isRefreshing)
                .onHover { isRefreshHovered = $0 }
                .accessibilityLabel("Refresh data")
            }
            Spacer()
            Menu("Options") {
                Button("Refresh", action: onRefresh)
                    .keyboardShortcut("r", modifiers: .command)
                    .disabled(isRefreshing)
                Divider()
                SettingsLink { Text("Settings…") }
                Button("Quit", role: .destructive) { NSApplication.shared.terminate(nil) }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color(white: 0.105))
    }

    private func elapsedMinutes(since date: Date, now: Date) -> Int {
        max(0, Int(now.timeIntervalSince(date) / 60))
    }
}
