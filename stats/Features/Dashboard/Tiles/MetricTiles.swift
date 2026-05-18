import SwiftUI

struct MemoryTile: View {
    let used: UInt64
    let total: UInt64
    let usage: Double
    var spec: String? = nil
    var isHighlighted = false
    var onTap: () -> Void = {}

    private var available: UInt64 {
        total > used ? total - used : 0
    }

    var body: some View {
        GaugeMetricTile(
            title: "Memory",
            value: StatsFormatting.percentString(usage),
            subtitle: "\(StatsFormatting.byteString(available)) available",
            systemImage: "memorychip",
            progress: usage,
            detail: spec,
            isHighlighted: isHighlighted
        )
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
    }
}

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
                .frame(height: 30 )
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

struct BatteryTile: View {
    let battery: BatteryStats

    var body: some View {
        MetricTile(
            title: "Battery",
            value: value,
            systemImage: "battery.75percent",
            progress: battery.level,
            detail: battery.powerSource
        )
    }

    private var value: String {
        let chargingText = battery.isCharging ? "Charging" : battery.powerSource
        return "\(StatsFormatting.percentString(battery.level)) · \(chargingText)"
    }
}

struct GPUTile: View {
    let stats: GPUStats?
    var spec: String? = nil

    var body: some View {
        GaugeMetricTile(
            title: "GPU",
            value: stats.map { StatsFormatting.percentString($0.utilization) } ?? "--",
            subtitle: "",
            systemImage: "cpu",
            progress: stats?.utilization,
            detail: spec
        )
    }
}

struct ThermalTile: View {
    let temperature: Double?
    let thermalState: ProcessInfo.ThermalState

    var body: some View {
        StatsTile(title: "Thermal", systemImage: systemImage) {
            VStack(alignment: .leading, spacing: 4) {
                Text(primaryValue)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(primaryColor)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Text(secondaryValue)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }

    private var primaryValue: String {
        temperature.map { String(format: "%.1f°C", $0) } ?? StatsFormatting.thermalStateString(thermalState)
    }

    private var secondaryValue: String {
        if temperature == nil {
            return "System thermal pressure"
        }

        return "CPU die temperature · \(StatsFormatting.thermalStateString(thermalState)) pressure"
    }

    private var systemImage: String {
        switch thermalState {
        case .nominal:
            return "thermometer.low"
        case .fair:
            return "thermometer.medium"
        case .serious, .critical:
            return "thermometer.high"
        @unknown default:
            return "thermometer.medium"
        }
    }

    private var primaryColor: Color {
        switch thermalState {
        case .nominal:
            return .primary
        case .fair:
            return .yellow
        case .serious, .critical:
            return .red
        @unknown default:
            return .primary
        }
    }
}

private struct GaugeMetricTile: View {
    let title: String
    let value: String
    let subtitle: String
    let systemImage: String
    let progress: Double?
    var detail: String? = nil
    var isHighlighted = false
    var subtitleStyle = Color(white: 0.58)

    @Environment(\.tileDashboardHeight) private var tileHeight

    private var scale: CGFloat {
        tileHeight > 0 ? tileHeight / StatsTile<EmptyView>.dashboardHeight : 1
    }

    private var clampedProgress: Double {
        guard let progress, progress.isFinite else { return 0 }
        return max(0, min(progress, 1))
    }

    var body: some View {
        StatsTile(title: title, systemImage: systemImage, detail: detail, isHighlighted: isHighlighted) {
            Text(subtitle)
                .font(.caption.weight(.medium))
                .foregroundStyle(subtitleStyle)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Spacer(minLength: 0)

            ZStack(alignment: .bottom) {
                MetricGaugeArc(progress: 1)
                    .stroke(.quaternary, style: strokeStyle)

                MetricGaugeArc(progress: clampedProgress)
                    .stroke(gaugeColor, style: strokeStyle)
                    .animation(.easeOut(duration: 0.4), value: clampedProgress)

                VStack(spacing: 4) {
                    Text(value)
                        .font(.title3.weight(.semibold))
                        .monospacedDigit()
                }
                .padding(.bottom, 6 * scale)
            }
            .frame(width: 142 * scale, height: 72 * scale)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.bottom, 8 * scale)
        }
    }

    private var strokeStyle: StrokeStyle {
        StrokeStyle(lineWidth: 12 * scale, lineCap: .round)
    }

    private var gaugeColor: Color {
        switch clampedProgress {
        case ..<0.70:
            return Color(red: 0, green: 0xE2 / 255.0, blue: 0x73 / 255.0)
        case ..<0.90:
            return .yellow
        default:
            return .red
        }
    }
}

private struct MetricGaugeArc: InsettableShape {
    var progress: Double
    var insetAmount: CGFloat = 0

    var animatableData: AnimatablePair<Double, CGFloat> {
        get { AnimatablePair(progress, insetAmount) }
        set {
            progress = newValue.first
            insetAmount = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let clampedProgress = max(0, min(progress, 1))
        let radius = max(min(rect.width / 2, rect.height) - insetAmount, 0)
        let center = CGPoint(x: rect.midX, y: rect.maxY - insetAmount)
        let segmentCount = max(Int(ceil(clampedProgress * 48)), 1)

        var path = Path()

        for segment in 0...segmentCount {
            let segmentProgress = clampedProgress * Double(segment) / Double(segmentCount)
            let angle = Double.pi - (segmentProgress * Double.pi)
            let point = CGPoint(
                x: center.x + (cos(angle) * radius),
                y: center.y - (sin(angle) * radius)
            )

            if segment == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }

        return path
    }

    func inset(by amount: CGFloat) -> some InsettableShape {
        var shape = self
        shape.insetAmount += amount
        return shape
    }
}

private struct MetricTile: View {
    let title: String
    let value: String
    let systemImage: String
    let progress: Double?
    var detail: String? = nil
    var isHighlighted = false

    var body: some View {
        StatsTile(title: title, systemImage: systemImage, detail: detail, isHighlighted: isHighlighted) {
            Text(value)
                .font(.callout.weight(.medium))
                .foregroundStyle(.primary)
                .monospacedDigit()
                .lineLimit(2)
                .minimumScaleFactor(0.8)

            if let progress {
                ProgressView(value: max(0, min(progress, 1)))
                    .controlSize(.small)
            }
        }
    }
}

private struct DiskCapacityBar: View {
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
