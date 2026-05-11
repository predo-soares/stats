import AppKit
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
        HStack(alignment: .firstTextBaseline) {
            Text("Memory")
                .font(.title2.weight(.semibold))
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
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
            MemoryInfoTile(
                title: "Pressure",
                value: StatsFormatting.percentString(stats.pressure),
                description: pressureDescription(for: stats.pressure),
                systemImage: "gauge.with.dots.needle.67percent"
            )

            MemoryInfoTile(
                title: "Swap File",
                value: stats.swapTotal > 0 ? StatsFormatting.byteString(stats.swapUsed) : "None",
                description: "Drive space macOS can use when physical memory is under load.",
                systemImage: "internaldrive"
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

private struct MemoryInfoTile: View {
    let title: String
    let value: String
    let description: String
    let systemImage: String

    var body: some View {
        StatsTile(title: title, systemImage: systemImage) {
            VStack(alignment: .leading, spacing: 8) {
                Text(value)
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(minHeight: 92, alignment: .topLeading)
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
        if let icon = NSRunningApplication(processIdentifier: process.pid)?.icon {
            Image(nsImage: icon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 18, height: 18)
        } else {
            Image(systemName: "app.dashed")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 18, height: 18)
        }
    }

    private var rowBackground: Color {
        if isHovered {
            return Color.accentColor.opacity(0.14)
        }

        return isAlternate ? Color.white.opacity(0.04) : Color.clear
    }
}

struct DiskDetailView: View {
    let store: SystemStatsStore
    let onClose: () -> Void

    private var used: UInt64 { store.snapshot.diskUsed }
    private var total: UInt64 { store.snapshot.diskTotal }
    private var available: UInt64 { total > used ? total - used : 0 }
    private var usage: Double { store.snapshot.diskUsage }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            if total > 0 {
                overview
                infoGrid
                diskAccessSection
                Divider()
                components
            } else {
                unavailableState
            }
        }
        .padding(16)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Macintosh HD")
                    .font(.title2.weight(.semibold))
                Text("Storage details")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
    }

    private var overview: some View {
        HStack(spacing: 24) {
            DiskDonutView(used: used, available: available, total: total)
                .frame(width: 220, height: 220)

            VStack(alignment: .leading, spacing: 14) {
                DiskLegendItem(title: "Used", value: used, color: .primary)
                DiskLegendItem(title: "Available", value: available, color: .secondary)
                DiskLegendItem(title: "Total", value: total, color: Color(nsColor: .tertiaryLabelColor))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var infoGrid: some View {
        HStack(spacing: 12) {
            DiskInfoTile(
                title: "Usage",
                value: StatsFormatting.percentString(usage),
                description: usageDescription,
                systemImage: "gauge.with.dots.needle.67percent"
            )

            DiskInfoTile(
                title: "Available",
                value: StatsFormatting.byteString(available),
                description: "Free space reported by macOS for important usage.",
                systemImage: "internaldrive"
            )
        }
    }

    private var diskAccessSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Granular Storage Access")
                .font(.headline.weight(.semibold))

            Text("Category and file-level storage analysis may require folder permissions or Full Disk Access. macOS does not show a normal permission prompt for Full Disk Access, so you need to enable it in System Settings.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                Button("Open Full Disk Access") {
                    DiskAccessSupport.openFullDiskAccessSettings()
                }
                .buttonStyle(.borderedProminent)

                Text("Desktop, Documents, and Downloads can still use standard macOS folder prompts when the app accesses them.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color(nsColor: .separatorColor).opacity(0.35), lineWidth: 1)
        }
    }

    private var components: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Components")
                .font(.headline.weight(.semibold))

            VStack(spacing: 8) {
                DiskComponentRow(
                    title: "Used Space",
                    value: used,
                    total: total,
                    systemImage: "externaldrive.fill",
                    tint: .primary
                )

                DiskComponentRow(
                    title: "Available Space",
                    value: available,
                    total: total,
                    systemImage: "checkmark.circle",
                    tint: .secondary
                )
            }
        }
    }

    private var unavailableState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: "internaldrive")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("Disk information is unavailable")
                .font(.headline)
            Text("Refresh system stats to try reading storage capacity again.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 180, alignment: .center)
    }

    private var usageDescription: String {
        switch usage {
        case ..<0.70:
            return "Storage has comfortable free space."
        case ..<0.90:
            return "Storage is getting full; cleanup may help."
        default:
            return "Storage is nearly full. Free space soon."
        }
    }
}

private struct DiskDonutView: View {
    let used: UInt64
    let available: UInt64
    let total: UInt64

    private var usedFraction: Double {
        guard total > 0 else { return 0 }
        return min(max(Double(used) / Double(total), 0), 1)
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.08), lineWidth: 28)

            Circle()
                .trim(from: 0, to: usedFraction)
                .stroke(Color.primary, style: StrokeStyle(lineWidth: 28, lineCap: .butt))
                .rotationEffect(.degrees(-90))

            VStack(spacing: 4) {
                Text(StatsFormatting.byteString(available))
                    .font(.title.weight(.semibold))
                    .monospacedDigit()
                Text("of \(StatsFormatting.byteString(total)) available")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)
        }
        .padding(12)
    }
}

private struct DiskLegendItem: View {
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

private struct DiskInfoTile: View {
    let title: String
    let value: String
    let description: String
    let systemImage: String

    var body: some View {
        StatsTile(title: title, systemImage: systemImage) {
            VStack(alignment: .leading, spacing: 8) {
                Text(value)
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(minHeight: 92, alignment: .topLeading)
        }
    }
}

private struct DiskComponentRow: View {
    let title: String
    let value: UInt64
    let total: UInt64
    let systemImage: String
    let tint: Color

    private var fraction: Double {
        guard total > 0 else { return 0 }
        return min(max(Double(value) / Double(total), 0), 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(tint)
                    .frame(width: 18)

                Text(title)
                    .font(.callout.weight(.semibold))

                Spacer()

                Text(StatsFormatting.byteString(value))
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            ProgressView(value: fraction)
                .tint(tint)
                .controlSize(.small)
        }
        .padding(12)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color(nsColor: .separatorColor).opacity(0.35), lineWidth: 1)
        }
    }
}

enum DiskAccessSupport {
    private static let fullDiskAccessURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")
    private static let privacySettingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security")
    private static let systemSettingsAppURL = URL(fileURLWithPath: "/System/Applications/System Settings.app")

    static func openFullDiskAccessSettings() {
        if let fullDiskAccessURL, NSWorkspace.shared.open(fullDiskAccessURL) {
            return
        }

        if let privacySettingsURL, NSWorkspace.shared.open(privacySettingsURL) {
            return
        }

        NSWorkspace.shared.open(systemSettingsAppURL)
    }
}
