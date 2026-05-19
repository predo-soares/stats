import SwiftUI

struct TileDashboardHeightKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}

extension EnvironmentValues {
    var tileDashboardHeight: CGFloat {
        get { self[TileDashboardHeightKey.self] }
        set { self[TileDashboardHeightKey.self] = newValue }
    }
}

struct StatsTile<Content: View>: View {
    static var dashboardHeight: CGFloat { 156 }

    let title: String
    let systemImage: String
    var detail: String? = nil
    var isHighlighted = false
    @ViewBuilder let content: Content

    @State private var isHovered = false
    @Environment(\.tileDashboardHeight) private var tileHeight

    init(
        title: String,
        systemImage: String,
        detail: String? = nil,
        isHighlighted: Bool = false,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.systemImage = systemImage
        self.detail = detail
        self.isHighlighted = isHighlighted
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            TileHeader(title: title, systemImage: systemImage, detail: detail, isHighlighted: isHighlighted)
            content
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(height: tileHeight > 0 ? tileHeight : nil, alignment: .topLeading)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(white: 0.10).opacity(0.78))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(isHighlighted ? 0.09 : 0))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(isHovered ? 0.06 : 0))
        }
        .onHover { isHovered = $0 }
        .animation(.easeInOut(duration: 0.15), value: isHovered)
        .animation(.easeInOut(duration: 0.15), value: isHighlighted)
    }
}

private struct TileHeader: View {
    let title: String
    let systemImage: String
    let detail: String?
    let isHighlighted: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
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
                    .font(.callout.weight(.regular))
                    .foregroundStyle(Color.white.opacity(0.64))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
        }
    }
}
