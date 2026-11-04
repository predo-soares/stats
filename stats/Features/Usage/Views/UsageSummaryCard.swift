import Charts
import SwiftUI

struct UsageSummaryCard: View {
    @Binding var metric: UsageMetric
    @Binding var selectedPeriod: UsageComparisonPeriod

    let codex: CodexUsageProjection
    let cursor: CursorUsageProjection
    let codexComparison: UsageTokenComparison
    let cursorComparison: UsageTokenComparison
    let combinedCost: UsageCostResult?

    @State private var metricMenuHovered = false

    private let cardColor = Color(white: 0.14)
    private var totalTokens: Int { codex.totalTokens + cursor.totalTokens }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            metricMenu
            if metric == .cost, let combinedCost {
                costStatus(combinedCost)
            }
            HStack(spacing: 20) {
                metricChart
                VStack(alignment: .leading, spacing: 8) {
                    legendRow("Codex", color: .green, comparison: codexComparison)
                    legendRow("Cursor", color: .blue, comparison: cursorComparison)
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
        .font(.system(size: 18, weight: .semibold))
    }

    @ViewBuilder private var metricChart: some View {
        if metric == .tokens {
            Chart {
                SectorMark(angle: .value("Codex", codex.totalTokens), innerRadius: .ratio(0.67))
                    .foregroundStyle(.green)
                SectorMark(angle: .value("Cursor", cursor.totalTokens), innerRadius: .ratio(0.67))
                    .foregroundStyle(.blue)
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
            .frame(width: 132, height: 132)
            .accessibilityLabel("Combined token consumption")
            .accessibilityValue(UsageMetric.tokens.formatted(totalTokens))
        } else {
            RoundedRectangle(cornerRadius: 66)
                .fill(cardColor)
                .frame(width: 132, height: 132)
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
                Text(label).font(.subheadline.weight(.medium)).foregroundStyle(.primary)
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
