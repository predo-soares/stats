import AppKit
import SwiftUI

enum UsageProviderIdentity: String, CaseIterable, Sendable, Identifiable, Hashable {
    case codex
    case cursor
    case claude
    case pi
    case grok
    case zai
    case antigravity

    var id: String { rawValue }

    var name: String {
        switch self {
        case .codex: "Codex"
        case .cursor: "Cursor"
        case .claude: "Claude"
        case .pi: "Pi"
        case .grok: "Grok"
        case .zai: "Z.ai"
        case .antigravity: "Antigravity"
        }
    }

    var logoAssetName: String? {
        switch self {
        case .codex: "CodexLogo"
        case .cursor: "CursorLogo"
        case .claude: "ClaudeLogo"
        case .pi: "PiLogo"
        case .grok: nil
        case .zai: nil
        case .antigravity: nil
        }
    }

    var logoSystemName: String? {
        switch self {
        case .claude: "brain.head.profile"
        case .pi: "circle.hexagonpath"
        case .grok: "bolt.horizontal.circle"
        case .zai: "z.circle"
        case .antigravity: "sparkles"
        case .codex, .cursor: nil
        }
    }

    var enrollmentKey: String { rawValue }

    /// Supported providers stay unbadged. Future Experimental adapters extend this.
    var supportState: ProviderSupportState {
        switch self {
        case .codex, .cursor: .supported
        case .claude, .pi, .grok, .zai, .antigravity: .experimental
        }
    }

    /// Fresh enrollment defaults: nothing pre-selected until the user chooses or skips.
    var defaultEnrollmentEnabled: Bool { false }

    var enrollmentSummary: String {
        switch self {
        case .codex: "Local Codex sessions on this Mac"
        case .cursor: "Cursor account token history"
        case .claude: "Local Claude Code activity on this Mac"
        case .pi: "Local Pi runtime sessions with provider provenance"
        case .grok: "Local xAI Grok session activity"
        case .zai: "Z.ai usage via explicit API credential"
        case .antigravity: "Local Antigravity status-line snapshots"
        }
    }

    var collectionDisclosure: String {
        switch self {
        case .codex:
            "Collects timestamps, model identifiers, and token categories from local Codex sessions. Prompts, responses, tool arguments, source paths, and credentials are never retained."
        case .cursor:
            "Collects timestamps, model identifiers, and token categories reported for the signed-in Cursor workspace. Prompts, responses, source code, and credentials stay out of the usage ledger."
        case .claude:
            "Collects timestamps, model identifiers, and token categories from local Claude Code project transcripts. Prompts, responses, tool arguments, source paths, and credentials are never retained."
        case .pi:
            "Collects timestamps, token categories, model, and underlying provider from local Pi session metadata. Pi totals stay separate from direct provider cards. Prompts, responses, tool arguments, source paths, and credentials are never retained."
        case .grok:
            "Collects timestamps, model identifiers, and token categories from local Grok session signals/transcripts. Prompts, responses, tool arguments, source paths, and credentials are never retained."
        case .zai:
            "Requires an explicit Z.ai API key stored only in Keychain. Collects redacted model token rollups from the usage monitor API. Credentials never enter the ledger, logs, diagnostics, or exports."
        case .antigravity:
            "Collects model, session token parts, and quota fractions from sanitized Antigravity status-line snapshots. Prompts, workspace paths, credentials, and raw payloads are never retained."
        }
    }

    var connectionActionLabel: String {
        switch self {
        case .codex: "Use local sessions"
        case .cursor: "Connect account"
        case .claude: "Use local projects"
        case .pi: "Use local Pi sessions"
        case .grok: "Use local Grok sessions"
        case .zai: "Connect with API key"
        case .antigravity: "Use local snapshots"
        }
    }
}

struct ProviderBrandLogo: View {
    let provider: UsageProviderIdentity
    var size: CGFloat = 18

    var body: some View {
        Group {
            if let asset = provider.logoAssetName, NSImage(named: asset) != nil {
                Image(asset)
                    .resizable()
                    .scaledToFit()
            } else if let systemName = provider.logoSystemName {
                Image(systemName: systemName)
                    .symbolRenderingMode(.hierarchical)
            } else if let asset = provider.logoAssetName {
                Image(asset)
                    .resizable()
                    .scaledToFit()
            }
        }
        .frame(width: size, height: size)
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
                ProviderBrandLogo(provider: provider, size: 18)
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
