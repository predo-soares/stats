import Foundation

/// Persists which providers the user wants enabled, independently from credentials.
/// First-launch onboarding writes here; Settings edits the same selection later.
struct ProviderEnrollmentStore {
    static let completedKey = "provider.enrollment.completed"
    static let selectionPrefix = "provider.enrollment.enabled."

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var hasCompletedEnrollment: Bool {
        get { defaults.bool(forKey: Self.completedKey) }
        nonmutating set { defaults.set(newValue, forKey: Self.completedKey) }
    }

    func isEnabled(_ provider: UsageProviderIdentity) -> Bool {
        let key = Self.selectionPrefix + provider.enrollmentKey
        if defaults.object(forKey: key) == nil {
            return provider.defaultEnrollmentEnabled
        }
        return defaults.bool(forKey: key)
    }

    func setEnabled(_ enabled: Bool, for provider: UsageProviderIdentity) {
        defaults.set(enabled, forKey: Self.selectionPrefix + provider.enrollmentKey)
    }

    func finish(with selection: Set<UsageProviderIdentity>) {
        for provider in UsageProviderIdentity.allCases {
            setEnabled(selection.contains(provider), for: provider)
        }
        hasCompletedEnrollment = true
    }

    func skipSelectingNone() {
        finish(with: [])
    }

    /// Returning installs should not see onboarding again. Prior usage covers installs that
    /// relied on implicit connection defaults without writing enrollment keys.
    func migrateLegacyConnectionsIfNeeded(hasPriorUsage: Bool) {
        guard defaults.object(forKey: Self.completedKey) == nil else { return }
        let hasLegacyKeys =
            defaults.object(forKey: "usage.connection.codex") != nil
            || defaults.object(forKey: "usage.connection.cursor") != nil
        guard hasLegacyKeys || hasPriorUsage else { return }
        let codex = defaults.object(forKey: "usage.connection.codex") as? Bool ?? true
        let cursor = defaults.object(forKey: "usage.connection.cursor") as? Bool ?? true
        setEnabled(codex, for: .codex)
        setEnabled(cursor, for: .cursor)
        defaults.set(codex, forKey: "usage.connection.codex")
        defaults.set(cursor, forKey: "usage.connection.cursor")
        hasCompletedEnrollment = true
    }
}

enum ProviderCatalog {
    static var enrollableProviders: [UsageProviderIdentity] {
        UsageProviderIdentity.allCases
    }

    static func descriptor(for provider: UsageProviderIdentity) -> ProviderDescriptor {
        ProviderDescriptor(
            identity: provider,
            supportState: provider.supportState,
            summary: provider.enrollmentSummary
        )
    }
}

struct ProviderDescriptor: Equatable, Sendable, Identifiable {
    var id: UsageProviderIdentity { identity }
    let identity: UsageProviderIdentity
    let supportState: ProviderSupportState
    let summary: String
}
