import SwiftUI

struct MemoryDetailView: View {
    let store: SystemStatsStore
    let onClose: () -> Void
    @AppStorage("stats.enableProcessTermination") private var enableProcessTermination = true
    @State private var killTarget: MemoryProcessStats? = nil
    @State private var isConfirmingKill = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            if let stats = store.snapshot.memoryStats {
                memoryOverview(stats: stats)
                memoryInfo(stats: stats)
            }

            if !store.snapshot.topMemoryProcesses.isEmpty {
                Divider()
                topConsumers
            }
        }
        .padding(16)
        .confirmationDialog(
            killTarget.map { "Quit or terminate \"\($0.name)\"?" } ?? "Quit process?",
            isPresented: $isConfirmingKill,
            titleVisibility: .visible
        ) {
            Button("Quit Process", role: .destructive) {
                guard let killTarget else { return }
                store.killProcess(pid: killTarget.pid)
                self.killTarget = nil
            }
            Button("Cancel", role: .cancel) {
                killTarget = nil
            }
        } message: {
            if let killTarget {
                Text("This sends SIGTERM to PID \(killTarget.pid). Current memory usage: \(StatsFormatting.byteString(killTarget.memoryBytes)).")
            }
        }
    }

    private var header: some View {
        DetailPanelHeader(title: "Memory", onClose: onClose)
    }

    private func memoryOverview(stats: MemoryStats) -> some View {
        HStack(spacing: 24) {
            MemoryDonutView(stats: stats)
                .frame(width: 220, height: 220)

            VStack(alignment: .leading, spacing: 14) {
                MemoryLegendItem(title: "App", value: stats.app, color: .primary)
                MemoryLegendItem(title: "Wired", value: stats.wired, color: .secondary)
                MemoryLegendItem(title: "Compressed", value: stats.compressed, color: Color(nsColor: .tertiaryLabelColor))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func memoryInfo(stats: MemoryStats) -> some View {
        HStack(spacing: 12) {
            DetailMetricTile(
                title: "Pressure",
                value: StatsFormatting.percentString(stats.pressure),
                description: pressureDescription(for: stats.pressure),
                systemImage: "gauge.with.dots.needle.67percent",
                valueFont: .title3.weight(.semibold),
                descriptionFont: .caption,
                descriptionLineLimit: 3,
                minHeight: 92,
                contentSpacing: 8
            )

            DetailMetricTile(
                title: "Swap File",
                value: stats.swapTotal > 0 ? StatsFormatting.byteString(stats.swapUsed) : "None",
                description: "Drive space macOS can use when physical memory is under load.",
                systemImage: "internaldrive",
                valueFont: .title3.weight(.semibold),
                descriptionFont: .caption,
                descriptionLineLimit: 3,
                minHeight: 92,
                contentSpacing: 8
            )
        }
    }

    private var topConsumers: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Top Consumers")
                .font(.headline.weight(.semibold))

            VStack(spacing: 2) {
                HStack(spacing: 8) {
                    Color.clear
                        .frame(width: 18, height: 1)
                    Text("Process name")
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("Usage")
                        .frame(width: 86, alignment: .trailing)
                    Color.clear
                        .frame(width: 48, height: 1)
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.bottom, 2)

                ForEach(Array(store.snapshot.topMemoryProcesses.prefix(6).enumerated()), id: \.element.id) { index, process in
                    MemoryConsumerRow(
                        process: process,
                        isAlternate: index.isMultiple(of: 2),
                        enableProcessTermination: enableProcessTermination
                    ) {
                        killTarget = process
                        isConfirmingKill = true
                    }
                }
            }
        }
    }

    private func pressureDescription(for pressure: Double) -> String {
        switch pressure {
        case ..<0.65:
            return "Memory has comfortable headroom for active apps."
        case ..<0.85:
            return "Memory is getting busy; closing unused apps can help."
        default:
            return "Consider quitting unused apps to reduce memory pressure."
        }
    }
}

private struct MemoryDonutView: View {
    let stats: MemoryStats

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.08), lineWidth: 28)

            segment(value: stats.app, start: 0, color: .primary)
            segment(value: stats.wired, start: appFraction, color: .secondary)
            segment(value: stats.compressed, start: appFraction + wiredFraction, color: Color(nsColor: .tertiaryLabelColor))

            VStack(spacing: 4) {
                Text(StatsFormatting.byteString(stats.available))
                    .font(.title.weight(.semibold))
                    .monospacedDigit()
                Text("of \(StatsFormatting.byteString(stats.total)) available")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)
        }
        .padding(12)
    }

    private func segment(value: UInt64, start: Double, color: Color) -> some View {
        Circle()
            .trim(from: start, to: min(start + fraction(value), 1))
            .stroke(color, style: StrokeStyle(lineWidth: 28, lineCap: .butt))
            .rotationEffect(.degrees(-90))
    }

    private var appFraction: Double { fraction(stats.app) }
    private var wiredFraction: Double { fraction(stats.wired) }

    private func fraction(_ value: UInt64) -> Double {
        guard stats.total > 0 else { return 0 }
        return Double(value) / Double(stats.total)
    }
}

private struct MemoryLegendItem: View {
    let title: String
    let value: UInt64
    let color: Color

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(color)
                .frame(width: 9, height: 9)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Text(StatsFormatting.byteString(value))
                    .font(.callout.weight(.semibold))
                    .monospacedDigit()
            }
        }
    }
}

private struct MemoryConsumerRow: View {
    let process: MemoryProcessStats
    let isAlternate: Bool
    let enableProcessTermination: Bool
    let onQuit: () -> Void

    @State private var isHovered = false
    @State private var isQuitHovered = false

    var body: some View {
        HStack(spacing: 8) {
            processIcon

            Text(process.name)
                .font(.caption.weight(.medium))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(StatsFormatting.byteString(process.memoryBytes))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .frame(width: 86, alignment: .trailing)

            if enableProcessTermination {
                Button("Quit", action: onQuit)
                    .buttonStyle(.plain)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(isQuitHovered ? .red : .secondary)
                    .frame(width: 48, alignment: .trailing)
                    .onHover { isQuitHovered = $0 }
            } else {
                Color.clear
                    .frame(width: 48, height: 1)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(rowBackground, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .animation(.easeInOut(duration: 0.12), value: isHovered)
    }

    @ViewBuilder
    private var processIcon: some View {
        ProcessAppIcon(pid: process.pid)
    }

    private var rowBackground: Color {
        if isHovered {
            return Color.accentColor.opacity(0.14)
        }

        return isAlternate ? Color.white.opacity(0.04) : Color.clear
    }
}
