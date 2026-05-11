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

    private var spec: String? {
        total > 0 ? StatsFormatting.byteString(total) : nil
    }

    var body: some View {
        GaugeMetricTile(
            title: "Disk",
            value: usage.map(StatsFormatting.percentString) ?? "--",
            subtitle: availableSubtitle,
            systemImage: "internaldrive",
            progress: usage,
            detail: spec,
            isHighlighted: isHighlighted
        )
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
    }

    private var availableSubtitle: String {
        guard total > 0 else { return "Unavailable" }
        let available = total > used ? total - used : 0
        return "\(StatsFormatting.byteString(available)) available"
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

    private var clampedProgress: Double {
        guard let progress, progress.isFinite else { return 0 }
        return max(0, min(progress, 1))
    }

    var body: some View {
        StatsTile(title: title, systemImage: systemImage, detail: detail, isHighlighted: isHighlighted, fixedHeight: StatsTile<EmptyView>.dashboardHeight) {
            Text(subtitle)
                .font(.caption.weight(.medium))
                .foregroundStyle(subtitleStyle)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Spacer(minLength: 12)

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
                .padding(.bottom, 6)
            }
            .frame(width: 142, height: 72)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.bottom, 8)
        }
    }

    private var strokeStyle: StrokeStyle {
        StrokeStyle(lineWidth: 12, lineCap: .round)
    }

    private var gaugeColor: Color {
        switch clampedProgress {
        case ..<0.70:
            return Color(white: 0.58)
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
        StatsTile(title: title, systemImage: systemImage, detail: detail, isHighlighted: isHighlighted, fixedHeight: StatsTile<EmptyView>.dashboardHeight) {
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
