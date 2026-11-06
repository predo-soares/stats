import SwiftUI

enum UsageProviderIdentity: String, CaseIterable, Sendable, Identifiable, Hashable {
    case codex
    case cursor

    var id: String { rawValue }

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

    var enrollmentKey: String { rawValue }

    /// Supported providers stay unbadged. Future Experimental adapters extend this.
    var supportState: ProviderSupportState {
        switch self {
        case .codex, .cursor: .supported
        }
    }

    /// Fresh enrollment defaults: nothing pre-selected until the user chooses or skips.
    var defaultEnrollmentEnabled: Bool { false }

    var enrollmentSummary: String {
        switch self {
        case .codex: "Local Codex sessions on this Mac"
        case .cursor: "Cursor account token history"
        }
    }

    var collectionDisclosure: String {
        switch self {
        case .codex:
            "Collects timestamps, model identifiers, and token categories from local Codex sessions. Prompts, responses, tool arguments, source paths, and credentials are never retained."
        case .cursor:
            "Collects timestamps, model identifiers, and token categories reported for the signed-in Cursor workspace. Prompts, responses, source code, and credentials stay out of the usage ledger."
        }
    }

    var connectionActionLabel: String {
        switch self {
        case .codex: "Use local sessions"
        case .cursor: "Connect account"
        }
    }
}

struct ProviderIdentityHeader: View {
    let provider: UsageProviderIdentity
    let plan: String
    var trailingLabel: String?
    var supportState: ProviderSupportState?

    var body: some View {
        HStack {
            HStack(spacing: 8) {
                Image(provider.logoAssetName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 18, height: 18)
                Text(provider.name).font(.headline.bold())
                Text(plan).font(.headline.weight(.medium)).foregroundStyle(.secondary)
                if let supportState {
                    ProviderSupportStateIndicator(state: supportState)
                }
            }
            Spacer()
            if let trailingLabel {
                Text(trailingLabel).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
