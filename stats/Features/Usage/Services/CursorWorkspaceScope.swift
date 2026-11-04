import Foundation

struct CursorWorkspaceScope: Sendable, Equatable, Identifiable, Hashable {
    let id: String
    let name: String
}

enum CursorWorkspaceScopeError: LocalizedError, Sendable {
    case noneAvailable
    case ambiguousSelection([CursorWorkspaceScope])
    case unknownScope(String)

    var errorDescription: String? {
        switch self {
        case .noneAvailable: "Cursor did not expose a usable workspace scope."
        case .ambiguousSelection: "Select one Cursor workspace before continuing."
        case .unknownScope: "Cursor did not confirm the selected workspace scope."
        }
    }
}

protocol CursorWorkspaceScopeSource: Sendable {
    func availableScopes(for session: CursorAuthenticatedSession) async throws -> [CursorWorkspaceScope]
}

/// The observed usage-events endpoint is account-scoped. Until a verified multi-workspace API is
/// confirmed, expose exactly one stable local scope keyed by account so histories stay isolated.
struct AccountDefaultCursorWorkspaceScopeSource: CursorWorkspaceScopeSource {
    func availableScopes(for session: CursorAuthenticatedSession) async throws -> [CursorWorkspaceScope] {
        [
            CursorWorkspaceScope(id: "default:\(session.accountID)", name: "Default workspace")
        ]
    }
}

struct CursorWorkspaceSelection: Sendable {
    let scope: CursorWorkspaceScope

    static func resolve(scopes: [CursorWorkspaceScope], preferredID: String?) throws -> CursorWorkspaceSelection {
        guard !scopes.isEmpty else { throw CursorWorkspaceScopeError.noneAvailable }
        if let preferredID {
            guard let match = scopes.first(where: { $0.id == preferredID }) else {
                throw CursorWorkspaceScopeError.unknownScope(preferredID)
            }
            return CursorWorkspaceSelection(scope: match)
        }
        guard scopes.count == 1, let only = scopes.first else {
            throw CursorWorkspaceScopeError.ambiguousSelection(scopes)
        }
        return CursorWorkspaceSelection(scope: only)
    }
}
