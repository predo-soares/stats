import Foundation

/// Lifecycle state for an independent provider refresh. A failed refresh never implies
/// that the provider has zero usage; callers retain the last successful value separately.
enum ProviderRefreshState: Sendable, Equatable {
    case disconnected
    case refreshing
    case fresh(observedAt: Date, cutoff: Date?)
    case stale(observedAt: Date, cutoff: Date?, error: String)
    case unavailable(String)

    var isUsable: Bool {
        switch self {
        case .fresh, .stale: true
        case .disconnected, .refreshing, .unavailable: false
        }
    }

    var errorMessage: String? {
        switch self {
        case .stale(_, _, let error), .unavailable(let error): error
        default: nil
        }
    }

    var observedAt: Date? {
        switch self {
        case .fresh(let observedAt, _), .stale(let observedAt, _, _): observedAt
        default: nil
        }
    }

    var cutoff: Date? {
        switch self {
        case .fresh(_, let cutoff), .stale(_, let cutoff, _): cutoff
        default: nil
        }
    }
}

struct ProviderRefreshSnapshot<Value: Sendable>: Sendable {
    let value: Value?
    let state: ProviderRefreshState

    static func refreshing(retaining value: Value?) -> Self {
        Self(value: value, state: .refreshing)
    }

    static func success(_ value: Value, observedAt: Date, cutoff: Date?) -> Self {
        Self(value: value, state: .fresh(observedAt: observedAt, cutoff: cutoff))
    }

    func failed(retaining value: Value? = nil, observedAt: Date, cutoff: Date?, error: String) -> Self {
        Self(value: value ?? self.value, state: .stale(observedAt: observedAt, cutoff: cutoff ?? state.cutoff, error: error))
    }
}
