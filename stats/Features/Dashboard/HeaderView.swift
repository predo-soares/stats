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
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 2) {
                    Text(modelName.isEmpty ? "Mac" : modelName)
                        .font(.title.weight(.semibold))

                    Text(macOSVersion)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Button("Recent Issues", action: onRecentIssuesTap)
                .buttonStyle(.plain)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }
}
