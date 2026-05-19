import SwiftUI

struct HeaderView: View {
    let modelName: String
    var onRecentIssuesTap: () -> Void = {}

    private var macOSVersion: String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return "macOS \(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
    }

    private var deviceSymbol: String {
        let name = modelName.lowercased()
        if name.contains("macbook") { return "laptopcomputer" }
        if name.contains("imac") { return "desktopcomputer" }
        if name.contains("mac mini") { return "macmini" }
        if name.contains("mac pro") { return "macpro.gen3" }
        if name.contains("mac studio") { return "macstudio" }
        return "desktopcomputer"
    }

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: deviceSymbol)
                    .font(.system(size: 28))
                    .foregroundStyle(Color.white.opacity(0.70))

                VStack(alignment: .leading, spacing: 2) {
                    Text(modelName.isEmpty ? "Mac" : modelName)
                        .font(.title.weight(.semibold))

                    Text(macOSVersion)
                        .font(.caption)
                        .foregroundStyle(Color.white.opacity(0.68))
                }
            }

            Spacer()

            HeaderIconButton(
                systemImage: "exclamationmark.triangle",
                accessibilityLabel: "Recent Issues",
                action: onRecentIssuesTap
            )
        }
    }
}

private struct HeaderIconButton: View {
    let systemImage: String
    let accessibilityLabel: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HeaderIconLabel(systemImage: systemImage, accessibilityLabel: accessibilityLabel)
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.white.opacity(0.68))
        .accessibilityLabel(accessibilityLabel)
        .help(accessibilityLabel)
    }
}

private struct HeaderIconLabel: View {
    let systemImage: String
    let accessibilityLabel: String

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 14, weight: .semibold))
            .frame(width: 28, height: 28)
            .contentShape(Rectangle())
            .accessibilityLabel(accessibilityLabel)
    }
}
