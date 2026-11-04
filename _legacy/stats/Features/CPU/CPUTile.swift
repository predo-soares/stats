import SwiftUI

private enum CPUTileConstants {
    static let fullProgress = 1.0
    static let lowLoadThreshold = 0.70
    static let highLoadThreshold = 0.90
    static let healthyGaugeColor = Color(red: 0, green: 0xE2 / 255.0, blue: 0x73 / 255.0)
    static let gaugeWidth: CGFloat = 142
    static let gaugeHeight: CGFloat = 72
    static let gaugeBottomPadding: CGFloat = 8
    static let centerLabelBottomPadding: CGFloat = 6
    static let strokeWidth: CGFloat = 12
    static let defaultSpacerHeight: CGFloat = 12
    static let gaugeAnimationDuration = 0.4
    static let gaugeSegments = 48.0
}

struct CPUTile: View {
    let stats: CPUStats?
    var spec: String? = nil
    var isHighlighted = false
    let onTap: () -> Void

    var body: some View {
        StatsTile(title: "CPU", systemImage: "cpu", detail: spec, isHighlighted: isHighlighted) {
            Spacer(minLength: 0)

            CPUGaugeView(stats: stats)
                .accessibilityLabel("CPU usage gauge")
                .accessibilityValue(stats.map { StatsFormatting.percentString($0.active) } ?? "Measuring")
        }
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
    }
}

private struct CPUGaugeView: View {
    let stats: CPUStats?

    @Environment(\.tileDashboardHeight) private var tileHeight

    private var scale: CGFloat {
        tileHeight > 0 ? tileHeight / StatsTile<EmptyView>.dashboardHeight : 1
    }

    private var active: Double {
        guard let v = stats?.active, v.isFinite else { return 0 }
        return max(0, min(v, 1))
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            GaugeArc(progress: CPUTileConstants.fullProgress)
                .stroke(.quaternary, style: strokeStyle)

            GaugeArc(progress: active)
                .stroke(gaugeColor, style: strokeStyle)
                .animation(.easeOut(duration: CPUTileConstants.gaugeAnimationDuration), value: active)

            VStack(spacing: 4) {
                Text(stats.map { StatsFormatting.percentString($0.active) } ?? "--")
                    .font(.title2.weight(.semibold))
                    .monospacedDigit()
            }
            .padding(.bottom, CPUTileConstants.centerLabelBottomPadding * scale)
        }
        .frame(width: CPUTileConstants.gaugeWidth * scale, height: CPUTileConstants.gaugeHeight * scale)
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var strokeStyle: StrokeStyle {
        StrokeStyle(lineWidth: CPUTileConstants.strokeWidth * scale, lineCap: .round)
    }

    private var gaugeColor: Color {
        switch active {
        case ..<CPUTileConstants.lowLoadThreshold:
            return CPUTileConstants.healthyGaugeColor
        case ..<CPUTileConstants.highLoadThreshold:
            return .yellow
        default:
            return .red
        }
    }
}

private struct GaugeArc: InsettableShape {
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
        let clampedProgress = max(0, min(progress, CPUTileConstants.fullProgress))
        let radius = max(min(rect.width / 2, rect.height) - insetAmount, 0)
        let center = CGPoint(x: rect.midX, y: rect.maxY - insetAmount)
        let segmentCount = max(Int(ceil(clampedProgress * CPUTileConstants.gaugeSegments)), 1)

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

private struct CPUBreakdownView: View {
    let stats: CPUStats?

    var body: some View {
        VStack(spacing: 5) {
            CPUBreakdownRow(title: "System", value: stats?.system)
            CPUBreakdownRow(title: "User", value: stats?.user)
            CPUBreakdownRow(title: "Idle", value: stats?.idle)
        }
    }
}

private struct CPUBreakdownRow: View {
    let title: String
    let value: Double?

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .foregroundStyle(.secondary)

            Spacer(minLength: 8)

            Text(value.map(StatsFormatting.percentString) ?? "--")
                .monospacedDigit()
        }
        .font(.caption)
    }
}
