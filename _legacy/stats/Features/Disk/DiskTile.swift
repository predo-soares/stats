import SwiftUI

struct DiskTile: View {
    let used: UInt64
    let total: UInt64
    let usage: Double?
    var isHighlighted = false
    var onTap: () -> Void = {}

    @Environment(\.tileDashboardHeight) private var tileHeight

    private var scale: CGFloat {
        tileHeight > 0 ? tileHeight / StatsTile<EmptyView>.dashboardHeight : 1
    }

    private var spec: String? {
        total > 0 ? compactDiskValue(total) : nil
    }

    private var available: UInt64 {
        total > used ? total - used : 0
    }

    var body: some View {
        StatsTile(title: "Disk", systemImage: "internaldrive", detail: spec, isHighlighted: isHighlighted) {
            Spacer()
            HStack(alignment: .top) {
                diskMetricColumn(title: "Used", value: compactDiskValue(used))
                Spacer()
                diskMetricColumn(title: "Available", value: compactDiskValue(available))
            }
            .padding(.bottom, 4)

            DiskCapacityBar(progress: usage ?? 0)
                .frame(height: 30)
        }
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
    }

    @ViewBuilder
    private func diskMetricColumn(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(.caption, weight: .medium))
                .foregroundStyle(Color(white: 0.58))

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                let parts = splitDiskValue(value)

                Text(parts.number)
                    .font(.system(.title2, weight: .semibold))
                    .foregroundStyle(.white)
                    .monospacedDigit()

                Text(parts.unit)
                    .font(.system(.caption, weight: .medium))
                    .foregroundStyle(Color(white: 0.38))
                    .lineLimit(1)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func compactDiskValue(_ bytes: UInt64) -> String {
        guard bytes > 0 else { return "0 GB" }

        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useGB]
        formatter.countStyle = .file
        formatter.includesUnit = true
        formatter.isAdaptive = false
        formatter.zeroPadsFractionDigits = false

        let rawValue = formatter.string(fromByteCount: Int64(bytes))
        let cleanedValue = rawValue.replacingOccurrences(of: ".0 GB", with: " GB")
        return cleanedValue
    }

    private func splitDiskValue(_ value: String) -> (number: String, unit: String) {
        let parts = value.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        guard parts.count == 2 else { return (value, "") }
        return (String(parts[0]), String(parts[1]))
    }
}

struct DiskCapacityBar: View {
    let progress: Double

    private var clampedProgress: Double {
        guard progress.isFinite else { return 0 }
        return max(0, min(progress, 1))
    }

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: geo.size.height / 4, style: .continuous)
                    .fill(Color.white.opacity(0.32))

                RoundedRectangle(cornerRadius: geo.size.height / 4, style: .continuous)
                    .fill(Color.white.opacity(0.78))
                    .frame(width: max(width * clampedProgress, geo.size.height))
            }
        }
    }
}
