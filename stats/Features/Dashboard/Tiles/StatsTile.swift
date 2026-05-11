import SwiftUI

struct StatsTile<Content: View>: View {
    static var dashboardHeight: CGFloat { 156 }

    let title: String
    let systemImage: String
    var detail: String? = nil
    var isHighlighted = false
    var fixedHeight: CGFloat? = nil
    @ViewBuilder let content: Content

    @State private var isHovered = false

    init(
        title: String,
        systemImage: String,
        detail: String? = nil,
        isHighlighted: Bool = false,
        fixedHeight: CGFloat? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.systemImage = systemImage
        self.detail = detail
        self.isHighlighted = isHighlighted
        self.fixedHeight = fixedHeight
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            TileHeader(title: title, systemImage: systemImage, detail: detail, isHighlighted: isHighlighted)
            content
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(height: fixedHeight, alignment: .topLeading)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(0.04))
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(isHighlighted ? 0.10 : 0))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(isHovered ? 0.08 : 0))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(borderColor, lineWidth: 1)
        }
        .onHover { isHovered = $0 }
        .animation(.easeInOut(duration: 0.15), value: isHovered)
        .animation(.easeInOut(duration: 0.15), value: isHighlighted)
    }

    private var borderColor: Color {
        isHighlighted ? Color.white.opacity(0.38) : Color(nsColor: .separatorColor).opacity(0.45)
    }
}

private struct TileHeader: View {
    let title: String
    let systemImage: String
    let detail: String?
    let isHighlighted: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(isHighlighted ? Color.primary : Color(nsColor: .secondaryLabelColor))
                .frame(width: 18)

            Text(title)
                .font(.headline)
                .lineLimit(1)

            Spacer(minLength: 0)

            if let detail, !detail.isEmpty {
                Text(detail)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(Color(white: 0.58))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
        }
    }
}
