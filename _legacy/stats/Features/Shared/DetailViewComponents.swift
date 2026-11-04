import AppKit
import SwiftUI

struct DetailPanelHeader<Actions: View>: View {
    let title: String
    let subtitle: String?
    let onClose: () -> Void
    @ViewBuilder let actions: Actions

    init(
        title: String,
        subtitle: String? = nil,
        onClose: @escaping () -> Void,
        @ViewBuilder actions: () -> Actions = { EmptyView() }
    ) {
        self.title = title
        self.subtitle = subtitle
        self.onClose = onClose
        self.actions = actions()
    }

    var body: some View {
        HStack(alignment: subtitle == nil ? .firstTextBaseline : .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.title2.weight(.semibold))
            }

            Spacer()

            actions

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
    }
}

struct DetailMetricTile: View {
    let title: String
    let value: String
    let description: String
    let systemImage: String
    var valueFont: Font = .callout.weight(.medium)
    var descriptionFont: Font = .caption2
    var descriptionLineLimit = 2
    var minHeight: CGFloat? = nil
    var contentSpacing: CGFloat = 4

    var body: some View {
        StatsTile(title: title, systemImage: systemImage) {
            VStack(alignment: .leading, spacing: contentSpacing) {
                Text(value)
                    .font(valueFont)
                    .foregroundStyle(.primary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Text(description)
                    .font(descriptionFont)
                    .foregroundStyle(.secondary)
                    .lineLimit(descriptionLineLimit)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(minHeight: minHeight, alignment: .topLeading)
        }
    }
}

struct ProcessAppIcon: View {
    let pid: pid_t
    var size: CGFloat = 18

    var body: some View {
        if let icon = NSRunningApplication(processIdentifier: pid)?.icon {
            Image(nsImage: icon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
        } else {
            Image(systemName: "app.dashed")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: size, height: size)
        }
    }
}
