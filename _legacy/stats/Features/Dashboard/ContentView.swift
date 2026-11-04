import SwiftUI

struct ContentView: View {
    let store: SystemStatsStore
    var isCPUDetailPanelOpen = false
    var isMemoryDetailPanelOpen = false
    var isDiskDetailPanelOpen = false
    var onIssueTap: (DiagnosticsIssueType) -> Void = { _ in }
    var onRecentIssuesTap: () -> Void = {}
    var onCPUTap: () -> Void = {}
    var onMemoryTap: () -> Void = {}
    var onDiskTap: () -> Void = {}

    private let tileSpacing: CGFloat = 12

    private var tileRowCount: Int {
        store.snapshot.battery != nil ? 3 : 2
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HeaderView(
                modelName: store.machineModelName,
                onRecentIssuesTap: onRecentIssuesTap
            )

//                diagnosticsSection

            GeometryReader { geo in
                let rows = CGFloat(tileRowCount)
                let tileH = max(80, (geo.size.height - tileSpacing * (rows - 1)) / rows)
                VStack(spacing: tileSpacing) {
                    HStack(alignment: .top, spacing: tileSpacing) {
                        CPUTile(
                            stats: store.snapshot.cpuStats,
                            spec: store.machineChipName.isEmpty ? nil : store.machineChipName,
                            isHighlighted: isCPUDetailPanelOpen,
                            onTap: onCPUTap
                        )
                        .frame(maxWidth: .infinity)

                        MemoryTile(
                            used: store.snapshot.memoryUsed,
                            total: store.snapshot.memoryTotal,
                            usage: store.snapshot.memoryUsage,
                            spec: store.machineMemoryString,
                            isHighlighted: isMemoryDetailPanelOpen,
                            onTap: onMemoryTap
                        )
                        .frame(maxWidth: .infinity)
                    }

                    HStack(alignment: .top, spacing: tileSpacing) {
                        DiskTile(
                            used: store.snapshot.diskUsed,
                            total: store.snapshot.diskTotal,
                            usage: store.snapshot.diskTotal > 0 ? store.snapshot.diskUsage : nil,
                            isHighlighted: isDiskDetailPanelOpen,
                            onTap: onDiskTap
                        )
                        .frame(maxWidth: .infinity)

                        NetworkTile(
                            downloadRate: store.snapshot.networkDownloadRate,
                            uploadRate: store.snapshot.networkUploadRate,
                            history: store.networkRateHistory,
                            spec: store.networkName.isEmpty ? nil : store.networkName
                        )
                        .frame(maxWidth: .infinity)
                    }

                    if let battery = store.snapshot.battery {
                        HStack(alignment: .top, spacing: tileSpacing) {
                            BatteryTile(battery: battery)
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
                .environment(\.tileDashboardHeight, tileH)
            }
            .frame(maxHeight: .infinity)

            DashboardFooter()
        }
        .padding(16)
        .frame(width: 460)
        .frame(maxHeight: .infinity)
    }

    private var diagnosticsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if store.activeIssues.isEmpty {
                Text("No active issues. Current system state looks healthy.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(spacing: 8) {
                    ForEach(Array(store.activeIssues.prefix(3))) { issue in
                        ActiveIssueRow(issue: issue) {
                            onIssueTap(issue.type)
                        }
                    }
                }
            }
        }
    }
}

private struct DashboardFooter: View {
    var body: some View {
        HStack(alignment: .center) {
            Text("Stats")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.white.opacity(0.68))

            Spacer()

            SettingsLink {
                Image(systemName: "gearshape")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
                    .accessibilityLabel("Settings")
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.white.opacity(0.68))
            .help("Settings")
        }
        .padding(.top, 2)
    }
}

private struct ActiveIssueRow: View {
    let issue: DiagnosticsIssueEvent
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 12) {
                Circle()
                    .fill(issue.severity.color)
                    .frame(width: 10, height: 10)
                    .padding(.top, 4)

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(issue.title)
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(.primary)
                        Spacer()
                        Text(issue.severity.label)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(issue.severity.color)
                    }

                    if !issue.context.contributors.isEmpty {
                        Text(issue.context.contributors.map(\.name).joined(separator: ", "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Text(issue.suggestedAction)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }
            }
            .padding(10)
            .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
