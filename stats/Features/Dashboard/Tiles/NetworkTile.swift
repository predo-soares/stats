import SwiftUI

struct NetworkTile: View {
    let downloadRate: UInt64?
    let uploadRate: UInt64?
    let history: [NetworkRateSample]
    var spec: String? = nil

    var body: some View {
        StatsTile(title: "Network", systemImage: "network", detail: spec, fixedHeight: StatsTile<EmptyView>.dashboardHeight) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    NetworkRateMetric(
                        title: "Down",
                        systemImage: "arrow.down",
                        value: downloadRate,
                        tint: .secondary
                    )

                    NetworkRateMetric(
                        title: "Up",
                        systemImage: "arrow.up",
                        value: uploadRate,
                        tint: .orange
                    )
                }

                NetworkHistoryGraph(history: history)
                    .frame(height: 74)
            }
        }
    }
}

private struct NetworkRateMetric: View {
    let title: String
    let systemImage: String
    let value: UInt64?
    let tint: Color

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(value.map(StatsFormatting.byteRateString) ?? "Measuring")
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct NetworkHistoryGraph: View {
    let history: [NetworkRateSample]

    private let downloadColor = Color.secondary
    private let uploadColor = Color.orange

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(0.03))

            Canvas { context, size in
                drawGrid(in: &context, size: size)
                drawSeries(history.map(\.downloadRate), color: downloadColor, in: &context, size: size)
                drawSeries(history.map(\.uploadRate), color: uploadColor, in: &context, size: size)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 8)
        }
        .overlay(alignment: .center) {
            if history.count < 2 {
                Text("Collecting traffic")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func drawGrid(in context: inout GraphicsContext, size: CGSize) {
        let gridColor = Color(nsColor: .separatorColor).opacity(0.2)
        let columns = 6
        let rows = 3

        for column in 0...columns {
            let x = size.width * CGFloat(column) / CGFloat(columns)
            var path = Path()
            path.move(to: CGPoint(x: x, y: 0))
            path.addLine(to: CGPoint(x: x, y: size.height))
            context.stroke(path, with: .color(gridColor), lineWidth: 0.5)
        }

        for row in 0...rows {
            let y = size.height * CGFloat(row) / CGFloat(rows)
            var path = Path()
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: size.width, y: y))
            context.stroke(path, with: .color(gridColor), lineWidth: 0.5)
        }
    }

    private func drawSeries(
        _ values: [UInt64],
        color: Color,
        in context: inout GraphicsContext,
        size: CGSize
    ) {
        guard values.count > 1 else { return }

        let maxDownload = history.map(\.downloadRate).max() ?? 0
        let maxUpload = history.map(\.uploadRate).max() ?? 0
        let maxValue = Swift.max(Swift.max(maxDownload, maxUpload), 1)
        var path = Path()

        for (index, value) in values.enumerated() {
            let point = point(
                for: value,
                at: index,
                count: values.count,
                maxValue: maxValue,
                size: size
            )

            if index == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }

        context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 1.6, lineJoin: .round))
    }

    private func point(
        for value: UInt64,
        at index: Int,
        count: Int,
        maxValue: UInt64,
        size: CGSize
    ) -> CGPoint {
        let normalized = maxValue > 0 ? Double(value) / Double(maxValue) : 0
        let x = count > 1 ? size.width * CGFloat(index) / CGFloat(count - 1) : size.width
        let y = size.height * (1 - CGFloat(normalized))
        return CGPoint(x: x, y: y)
    }
}
