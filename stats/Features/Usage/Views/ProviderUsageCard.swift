import SwiftUI

struct ProviderCardPresentation {
    let provider: UsageProviderIdentity
    let plan: String
    let trailingLabel: String?
    let contentSpacing: CGFloat
    let messagesBeforeQuota: [ProviderCardMessage]
    let quota: ProviderQuotaContent
    let details: ProviderCardDetails
}

enum ProviderQuotaContent {
    case windows([ProviderQuotaWindowPresentation])
    case message(ProviderCardMessage)
}

struct ProviderQuotaWindowPresentation: Identifiable {
    let id: String
    let name: String
    let remainingFraction: Double
    let resetsAt: Date?
}

struct ProviderCardDetails {
    let rows: [ProviderMetricRow]
    let totalTokens: Int
    let showsDividerBeforeTotal: Bool
    let models: [UsageModelTotal]
    let status: ProviderCardMessage
}

struct ProviderMetricRow: Identifiable {
    let name: String
    let tokens: Int

    var id: String { name }
}

struct ProviderCardMessage {
    enum Style {
        case secondary
        case warning
        case error
        case progress
    }

    let text: String
    let style: Style
}

struct ProviderUsageCard: View {
    let presentation: ProviderCardPresentation
    @Binding var isExpanded: Bool

    @State private var isHovered = false

    private let cardColor = Color(white: 0.14)

    var body: some View {
        VStack(alignment: .leading, spacing: presentation.contentSpacing) {
            ProviderIdentityHeader(
                provider: presentation.provider,
                plan: presentation.plan,
                trailingLabel: presentation.trailingLabel,
                supportState: presentation.provider.supportState
            )
            ForEach(presentation.messagesBeforeQuota, id: \.text) { message in
                ProviderCardMessageView(message: message)
            }
            quotaContent
            if isExpanded {
                ProviderUsageDetails(provider: presentation.provider, details: presentation.details)
            }
        }
        .padding(14)
        .background(cardColor, in: RoundedRectangle(cornerRadius: 18))
        .overlay(alignment: .bottom) {
            viewMoreOverlay(visible: isHovered && !isExpanded)
        }
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .contentShape(RoundedRectangle(cornerRadius: 18))
        .onHover { isHovered = $0 }
        .onTapGesture { isExpanded.toggle() }
    }

    @ViewBuilder private var quotaContent: some View {
        switch presentation.quota {
        case .windows(let windows):
            ForEach(windows) { window in
                VisibleUsageMetric(provider: presentation.provider, name: window.name) {
                UsageQuotaWindow(
                    name: window.name,
                    remainingFraction: window.remainingFraction,
                    resetsAt: window.resetsAt
                )
                }
            }
        case .message(let message):
            ProviderCardMessageView(message: message)
        }
    }

    @ViewBuilder private func viewMoreOverlay(visible: Bool) -> some View {
        if visible {
            ZStack(alignment: .bottom) {
                LinearGradient(colors: [.clear, cardColor], startPoint: .top, endPoint: .bottom)
                    .frame(height: 42)
                Text("View more")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 10)
            }
            .frame(height: 42)
            .allowsHitTesting(false)
        }
    }
}

private struct ProviderUsageDetails: View {
    let provider: UsageProviderIdentity
    let details: ProviderCardDetails

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(details.rows) { row in
                VisibleUsageMetric(provider: provider, name: row.name) { tokenRow(row) }
            }
            if details.showsDividerBeforeTotal {
                Divider().overlay(.white.opacity(0.1))
            }
            VisibleUsageMetric(provider: provider, name: "Today total") { totalRow }
            providerDetails
            ProviderCardMessageView(message: details.status)
        }
    }

    private func tokenRow(_ row: ProviderMetricRow) -> some View {
        HStack(spacing: 12) {
            Text(row.name)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .layoutPriority(1)
            Spacer(minLength: 8)
            Text(UsageMetric.tokens.formatted(row.tokens))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .fixedSize(horizontal: true, vertical: false)
        }
        .font(.system(size: 12, weight: .medium))
    }

    private var totalRow: some View {
        HStack(spacing: 12) {
            Text("Today total").font(.subheadline.bold()).lineLimit(1)
            Spacer(minLength: 8)
            Text(UsageMetric.tokens.formatted(details.totalTokens))
                .font(.subheadline.bold())
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .fixedSize(horizontal: true, vertical: false)
        }
    }

    @ViewBuilder private var providerDetails: some View {
        if !details.models.isEmpty {
            VisibleUsageMetric(provider: provider, name: "Models") {
            DisclosureGroup("Models") {
                ForEach(details.models.prefix(5)) { model in
                    HStack {
                        Text(model.model).lineLimit(1).foregroundStyle(.secondary)
                        Spacer()
                        Text(UsageMetric.tokens.formatted(model.totalTokens)).monospacedDigit()
                    }
                    .font(.caption)
                }
            }
            .font(.caption.bold())
            }
        }
    }
}

private struct ProviderCardMessageView: View {
    let message: ProviderCardMessage

    var body: some View {
        switch message.style {
        case .secondary:
            Text(message.text).font(.caption).foregroundStyle(.secondary)
        case .warning:
            Text(message.text).font(.caption).foregroundStyle(.orange)
        case .error:
            Text(message.text).font(.caption).foregroundStyle(.red)
        case .progress:
            ProgressView(message.text).font(.caption)
        }
    }
}
