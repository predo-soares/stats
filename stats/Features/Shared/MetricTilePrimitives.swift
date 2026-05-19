import SwiftUI

struct GaugeMetricTile: View {
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

struct MetricTile: View {
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
