import SwiftUI

struct RecentIssuesDetailView: View {
    let store: SystemStatsStore
    let onClose: () -> Void
    let onIssueTap: (DiagnosticsIssueType) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            if store.recentIssues.isEmpty {
                emptyState
            } else {
                issuesList
            }
        }
        .padding(16)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Recent Issues")
                    .font(.title2.weight(.semibold))
                Text("Resolved diagnostics history")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if !store.recentIssues.isEmpty {
                Button("Clear") {
                    store.clearRecentIssueHistory()
                }
                .buttonStyle(.plain)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.trailing, 6)
            }

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("No recent resolved issues.")
                .font(.callout)
                .foregroundStyle(.secondary)

            Text("Resolved diagnostics will appear here after the app detects and closes an issue.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var issuesList: some View {
        ScrollView {
            VStack(spacing: 8) {
                ForEach(store.recentIssues) { issue in
                    Button {
                        onIssueTap(issue.type)
                    } label: {
                        HStack(alignment: .top, spacing: 12) {
                            Circle()
                                .fill(issue.severity.color)
                                .frame(width: 10, height: 10)
                                .padding(.top, 4)

                            VStack(alignment: .leading, spacing: 4) {
                                HStack(alignment: .firstTextBaseline) {
                                    Text(issue.title)
                                        .font(.callout.weight(.semibold))
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                    Spacer()
                                    Text(issue.severity.label)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(issue.severity.color)
                                }

                                Text(summary(for: issue))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)

                                if !issue.suggestedAction.isEmpty {
                                    Text(issue.suggestedAction)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .multilineTextAlignment(.leading)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }

                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.tertiary)
                                .padding(.top, 4)
                        }
                        .padding(10)
                        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func summary(for issue: DiagnosticsIssueEvent) -> String {
        let relative = issue.resolvedAt?.formatted(.relative(presentation: .named)) ?? "recently"
        return "Resolved \(relative) · lasted \(durationText(for: issue))"
    }

    private func durationText(for issue: DiagnosticsIssueEvent) -> String {
        let endDate = issue.resolvedAt ?? issue.lastSeenAt
        let duration = max(endDate.timeIntervalSince(issue.openedAt), 0)
        let minutes = Int(duration / 60)
        if minutes >= 60 {
            let hours = minutes / 60
            let remainingMinutes = minutes % 60
            return remainingMinutes > 0 ? "\(hours)h \(remainingMinutes)m" : "\(hours)h"
        }

        return "\(max(minutes, 1))m"
    }
}
