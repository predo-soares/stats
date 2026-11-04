import SwiftUI

enum UsageProviderIdentity {
    case codex
    case cursor

    var name: String {
        switch self {
        case .codex: "Codex"
        case .cursor: "Cursor"
        }
    }

    var logoAssetName: String {
        switch self {
        case .codex: "CodexLogo"
        case .cursor: "CursorLogo"
        }
    }
}

struct ProviderIdentityHeader: View {
    let provider: UsageProviderIdentity
    let plan: String
    var trailingLabel: String?

    var body: some View {
        HStack {
            HStack(spacing: 8) {
                Image(provider.logoAssetName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 18, height: 18)
                Text(provider.name).font(.headline.bold())
                Text(plan).font(.headline.weight(.medium)).foregroundStyle(.secondary)
            }
            Spacer()
            if let trailingLabel {
                Text(trailingLabel).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
