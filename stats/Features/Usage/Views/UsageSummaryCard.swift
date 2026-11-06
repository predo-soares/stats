import Charts
import SwiftUI

struct UsageSummaryCard: View {
    @Binding var metric: UsageMetric
    @Binding var selectedPeriod: UsageComparisonPeriod

    let codex: CodexUsageProjection
    let cursor: CursorUsageProjection
    let claude: LocalUsageProjection?
    let codexComparison: UsageTokenComparison
    let cursorComparison: UsageTokenComparison
    let claudeComparison: UsageTokenComparison?
    let combinedCost: UsageCostResult?

    @State private var metricMenuHovered = false

    private let cardColor = Color(white: 0.14)
    private let claudeColor = Color(red: 0.85, green: 0.45, blue: 0.22)
    private var totalTokens: Int {
        codex.totalTokens + cursor.totalTokens + (claude?.totalTokens ?? 0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            metricMenu
            if metric == .cost, let combinedCost {
                costStatus(combinedCost)
            }
            HStack(spacing: 14) {
                metricChart
                VStack(alignment: .leading, spacing: 8) {
                    legendRow("Codex", color: .green, comparison: codexComparison)
                    legendRow("Cursor", color: .blue, comparison: cursorComparison)
                    if let claude, let claudeComparison {
                        legendRow("Claude", color: claudeColor, comparison: claudeComparison)
                    }
                }
                Spacer()
            }
            UsagePeriodPicker(selection: $selectedPeriod)
                .frame(maxWidth: .infinity)
        }
        .padding(16)
        .background(cardColor, in: RoundedRectangle(cornerRadius: 18))
    }

    private var metricMenu: some View {
        HStack {
            Menu {
                ForEach(UsageMetric.allCases) { option in
                    Button(option.rawValue) { metric = option }
                }
            } label: {
                HStack(spacing: 5) {
                    Text(metric.rawValue)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2.weight(.semibold))
                }
                .padding(.vertical, 3)
                .padding(.horizontal, 5)
                .background(metricMenuHovered ? Color.white.opacity(0.1) : .clear, in: RoundedRectangle(cornerRadius: 6))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .onHover { metricMenuHovered = $0 }
            Spacer()
        }
        .font(.system(size: 16, weight: .semibold))
    }

    @ViewBuilder private var metricChart: some View {
        if metric == .tokens {
            Chart {
                SectorMark(angle: .value("Codex", max(codex.totalTokens, 0)), innerRadius: .ratio(0.67))
                    .foregroundStyle(.green)
                SectorMark(angle: .value("Cursor", max(cursor.totalTokens, 0)), innerRadius: .ratio(0.67))
                    .foregroundStyle(.blue)
                if let claude, claude.totalTokens > 0 {
                    SectorMark(angle: .value("Claude", claude.totalTokens), innerRadius: .ratio(0.67))
                        .foregroundStyle(claudeColor)
                }
            }
            .chartLegend(.hidden)
            .chartBackground { _ in
                VStack(spacing: 2) {
                    Text(UsageMetric.tokens.formatted(totalTokens))
                        .font(.title2.bold())
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    Text(selectedPeriod.title).font(.caption).foregroundStyle(.secondary)
                }
            }
            .frame(width: 112, height: 112)
            .accessibilityLabel("Combined token consumption")
            .accessibilityValue(UsageMetric.tokens.formatted(totalTokens))
        } else {
            RoundedRectangle(cornerRadius: 66)
                .fill(cardColor)
                .frame(width: 112, height: 112)
                .overlay {
                    Text(formattedCost(combinedCost))
                        .font(.title3.bold())
                        .monospacedDigit()
                        .minimumScaleFactor(0.6)
                }
                .accessibilityLabel("Combined estimated cost")
        }
    }

    private func legendRow(_ label: String, color: Color, comparison: UsageTokenComparison) -> some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                Circle().fill(color).frame(width: 9, height: 9)
                Text(label).font(.caption.weight(.medium)).foregroundStyle(.primary)
            }
            if metric == .tokens {
                UsageComparisonIndicator(comparison: comparison)
            } else {
                UsageComparisonDelta(value: 0, text: "--", muted: true)
            }
            Image(systemName: "info.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Comparison details")
                .help(comparisonHelpText)
        }
    }

    private var comparisonHelpText: String {
        switch selectedPeriod {
        case .today:
            "Percentage change in this period compared with yesterday."
        case .last7Days:
            "Percentage change in the last 7 days compared with the previous 7 days."
        case .last30Days:
            "Percentage change in the last 30 days compared with the previous 30 days."
        }
    }

    @ViewBuilder private func costStatus(_ result: UsageCostResult) -> some View {
        if result.isComplete {
            Text("Estimated Cost · pricing \(result.catalogRevision)")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            Text("Incomplete estimate · unknown models: " + result.estimate.unpricedModels.joined(separator: ", "))
                .font(.caption)
                .foregroundStyle(.orange)
                .lineLimit(2)
        }
    }

    private func formattedCost(_ result: UsageCostResult?) -> String {
        guard let result else { return "—" }
        if result.usageRecords > 0, result.estimate.pricedTokens == 0 { return "—" }
        return UsageMetric.cost.formattedCost(result.estimate.pricedCost)
    }
}
