import SwiftUI

private enum CPUDetailLayout {
    static let panelPadding: CGFloat = 16
    static let sectionSpacing: CGFloat = 16
    static let processSectionSpacing: CGFloat = 10
    static let processRowSpacing: CGFloat = 8
    static let processRowsSpacing: CGFloat = 2
    static let processIconWidth: CGFloat = 18
    static let processUsageWidth: CGFloat = 72
    static let processPIDWidth: CGFloat = 58
    static let processMemoryWidth: CGFloat = 86
    static let quitActionWidth: CGFloat = 48
    static let rowHorizontalPadding: CGFloat = 8
    static let rowVerticalPadding: CGFloat = 5
    static let rowCornerRadius: CGFloat = 5
    static let closeButtonSize: CGFloat = 11
    static let minVisibleRows = 4
    static let defaultVisibleRows = 6
    static let maxVisibleRows = 10
    static let rowCountOptions = [4, 6, 8, 10]
    static let hoverOpacity = 0.08
    static let alternateRowOpacity = 0.04
}

struct CPUDetailView: View {
    let store: SystemStatsStore
    let onClose: () -> Void

    @AppStorage("stats.enableProcessTermination") private var enableProcessTermination = true
    @AppStorage("stats.cpuDetailVisibleProcessCount") private var visibleProcessCount = CPUDetailLayout.defaultVisibleRows
    @State private var killTarget: RunningProcessStats? = nil
    @State private var isConfirmingKill = false
    @State private var displayedProcesses: [RunningProcessStats] = []
    @State private var isProcessListHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: CPUDetailLayout.sectionSpacing) {
            header
            chart
            systemInfo
            if !store.snapshot.topProcesses.isEmpty {
                processesSection
            }
        }
        .padding(CPUDetailLayout.panelPadding)
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
                Text("This sends SIGTERM to PID \(killTarget.pid). Current CPU usage: \(cpuString(killTarget.cpuPercent)).")
            }
        }
        .onAppear {
            displayedProcesses = store.snapshot.topProcesses
        }
        .onChange(of: store.snapshot.topProcesses) { _, newValue in
            if !isProcessListHovered {
                displayedProcesses = newValue
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        DetailPanelHeader(
            title: "CPU Usage",
            subtitle: "Last \(store.cpuStatsHistory.count)s",
            onClose: onClose
        )
    }

    // MARK: - Chart

    private var chart: some View {
        CPUHistoryPanel(samples: store.cpuStatsHistory, currentStats: store.snapshot.cpuStats)
            .frame(height: 150)
    }

    // MARK: - System Info

    private var systemInfo: some View {
        HStack(spacing: 12) {
            ThermalTile(
                temperature: store.cpuTemperature,
                thermalState: store.thermalState
            )

            DetailMetricTile(
                title: "Uptime",
                value: uptimeString,
                description: "Time since last restart",
                systemImage: "clock",
                valueFont: .callout.weight(.medium),
                descriptionFont: .caption2,
                descriptionLineLimit: 2,
                contentSpacing: 4
            )
        }
    }

    private var uptimeString: String {
        let total = Int(ProcessInfo.processInfo.systemUptime)
        let days = total / 86400
        let hours = (total % 86400) / 3600
        let minutes = (total % 3600) / 60
        if days > 0 { return "\(days)d \(hours)h \(minutes)m" }
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(minutes)m"
    }

    // MARK: - Processes

    private var processesSection: some View {
        VStack(alignment: .leading, spacing: CPUDetailLayout.processSectionSpacing) {
            HStack(alignment: .center, spacing: 12) {
                Text("Top Consumers")
                    .font(.headline.weight(.semibold))

                Spacer(minLength: 0)

                Menu {
                    ForEach(CPUDetailLayout.rowCountOptions, id: \.self) { count in
                        processRowCountOption(count)
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text("\(clampedVisibleProcessCount) rows")
                            .font(.caption.weight(.medium))
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundStyle(.secondary)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }

            VStack(spacing: CPUDetailLayout.processRowsSpacing) {
                HStack(spacing: CPUDetailLayout.processRowSpacing) {
                    Color.clear
                        .frame(width: CPUDetailLayout.processIconWidth, height: 1)
                    Text("Process name")
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("PID")
                        .frame(width: CPUDetailLayout.processPIDWidth, alignment: .trailing)
                    Text("Memory")
                        .frame(width: CPUDetailLayout.processMemoryWidth, alignment: .trailing)
                    Text("Usage")
                        .frame(width: CPUDetailLayout.processUsageWidth, alignment: .trailing)
                    Color.clear
                        .frame(width: CPUDetailLayout.quitActionWidth, height: 1)
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, CPUDetailLayout.rowHorizontalPadding)
                .padding(.bottom, 2)

                let processes = Array(displayedProcesses.prefix(clampedVisibleProcessCount).enumerated())
                ForEach(processes, id: \.element.id) { index, process in
                    CPUConsumerRow(
                        process: process,
                        isAlternate: index.isMultiple(of: 2),
                        enableProcessTermination: enableProcessTermination
                    ) {
                        killTarget = process
                        isConfirmingKill = true
                    }
                }
            }
            .onHover { hovering in
                isProcessListHovered = hovering
                if !hovering {
                    displayedProcesses = store.snapshot.topProcesses
                }
            }
        }
    }

    private func cpuString(_ value: Double) -> String {
        StatsFormatting.processPercentString(value)
    }

    private var clampedVisibleProcessCount: Int {
        max(CPUDetailLayout.minVisibleRows, min(visibleProcessCount, CPUDetailLayout.maxVisibleRows))
    }

    @ViewBuilder
    private func processRowCountOption(_ count: Int) -> some View {
        Button {
            visibleProcessCount = count
        } label: {
            if clampedVisibleProcessCount == count {
                Label("\(count) rows", systemImage: "checkmark")
            } else {
                Text("\(count) rows")
            }
        }
    }

}

private struct CPUConsumerRow: View {
    let process: RunningProcessStats
    let isAlternate: Bool
    let enableProcessTermination: Bool
    let onQuit: () -> Void

    @State private var isHovered = false
    @State private var isQuitHovered = false

    var body: some View {
        HStack(spacing: CPUDetailLayout.processRowSpacing) {
            processIcon

            Text(process.name)
                .font(.caption.weight(.medium))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text("\(process.pid)")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .monospacedDigit()
                .frame(width: CPUDetailLayout.processPIDWidth, alignment: .trailing)

            Text(memoryString)
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .frame(width: CPUDetailLayout.processMemoryWidth, alignment: .trailing)

            Text(cpuString)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .frame(width: CPUDetailLayout.processUsageWidth, alignment: .trailing)

            if enableProcessTermination {
                Button("Quit", action: onQuit)
                    .buttonStyle(.plain)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(isQuitHovered ? .red : .secondary)
                    .frame(width: CPUDetailLayout.quitActionWidth, alignment: .trailing)
                    .onHover { isQuitHovered = $0 }
            } else {
                Color.clear
                    .frame(width: CPUDetailLayout.quitActionWidth, height: 1)
            }
        }
        .padding(.horizontal, CPUDetailLayout.rowHorizontalPadding)
        .padding(.vertical, CPUDetailLayout.rowVerticalPadding)
        .background(rowBackground, in: RoundedRectangle(cornerRadius: CPUDetailLayout.rowCornerRadius, style: .continuous))
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .animation(.easeInOut(duration: 0.12), value: isHovered)
    }

    @ViewBuilder
    private var processIcon: some View {
        ProcessAppIcon(pid: process.pid, size: CPUDetailLayout.processIconWidth)
    }

    private var rowBackground: Color {
        if isHovered {
            return Color.white.opacity(CPUDetailLayout.hoverOpacity)
        }

        return isAlternate ? Color.white.opacity(CPUDetailLayout.alternateRowOpacity) : Color.clear
    }

    private var cpuString: String {
        StatsFormatting.processPercentString(process.cpuPercent)
    }

    private var memoryString: String {
        StatsFormatting.byteString(process.residentMemory)
    }
}

private struct CPUHistoryPanel: View {
    let samples: [CPUStats]
    let currentStats: CPUStats?

    private let availableColor = Color.secondary
    private let userColor = Color.blue
    private let systemColor = Color.orange

    var body: some View {
        HStack(spacing: 22) {
            CPUHistoryGraph(
                samples: samples,
                userColor: userColor,
                systemColor: systemColor
            )
            .frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: 22) {
                legendItem(
                    value: currentStats.map { StatsFormatting.percentString($0.idle) } ?? "--",
                    label: "Available",
                    color: availableColor
                )
                legendItem(
                    value: currentStats.map { StatsFormatting.percentString($0.user) } ?? "--",
                    label: "User",
                    color: userColor
                )
                legendItem(
                    value: currentStats.map { StatsFormatting.percentString($0.system) } ?? "--",
                    label: "System",
                    color: systemColor
                )
            }
            .frame(width: 104, alignment: .leading)
        }
        .padding(0)
    }

    private func legendItem(value: String, label: String, color: Color) -> some View {
        HStack(spacing: 12) {
            Capsule()
                .fill(color)
                .frame(width: 6, height: 34)

            VStack(alignment: .leading, spacing: 3) {
                Text(value)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(color)
                    .monospacedDigit()
                Text(label)
                    .font(.callout)
                    .foregroundStyle(color)
            }
        }
    }
}

private struct CPUHistoryGraph: View {
    let samples: [CPUStats]
    let userColor: Color
    let systemColor: Color

    var body: some View {
        Canvas { context, size in
            drawGrid(in: &context, size: size)
            drawStackedArea(
                lowerValues: Array(repeating: 0, count: samples.count),
                upperValues: samples.map(\.system),
                color: systemColor,
                in: &context,
                size: size
            )
            drawStackedArea(
                lowerValues: samples.map(\.system),
                upperValues: samples.map { min($0.system + $0.user, 1) },
                color: userColor,
                in: &context,
                size: size
            )
        }
    }

    private func drawGrid(in context: inout GraphicsContext, size: CGSize) {
        let gridColor = Color(nsColor: .separatorColor).opacity(0.28)
        let columns = 26
        let rows = 14

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

    private func drawStackedArea(
        lowerValues: [Double],
        upperValues: [Double],
        color: Color,
        in context: inout GraphicsContext,
        size: CGSize
    ) {
        guard upperValues.count > 1, lowerValues.count == upperValues.count else { return }

        var areaPath = Path()
        for index in upperValues.indices {
            let point = point(for: upperValues[index], at: index, count: upperValues.count, size: size)
            if index == upperValues.startIndex {
                areaPath.move(to: point)
            } else {
                areaPath.addLine(to: point)
            }
        }

        for index in lowerValues.indices.reversed() {
            areaPath.addLine(to: point(for: lowerValues[index], at: index, count: lowerValues.count, size: size))
        }
        areaPath.closeSubpath()

        context.fill(areaPath, with: .color(color.opacity(0.22)))
        drawLine(upperValues, color: color.opacity(0.85), in: &context, size: size)
    }

    private func drawLine(_ values: [Double], color: Color, in context: inout GraphicsContext, size: CGSize) {
        guard values.count > 1 else { return }

        var path = Path()
        for (index, value) in values.enumerated() {
            let point = point(for: value, at: index, count: values.count, size: size)
            if index == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }

        context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
    }

    private func point(for value: Double, at index: Int, count: Int, size: CGSize) -> CGPoint {
        let clampedValue = max(0, min(value, 1))
        let x = count > 1 ? size.width * CGFloat(index) / CGFloat(count - 1) : size.width
        let y = size.height * (1 - CGFloat(clampedValue))
        return CGPoint(x: x, y: y)
    }
}
