import Foundation

@main
struct RunProviderRefreshStateSelfChecks {
    static func main() {
        let observed = Date(timeIntervalSince1970: 1_700_000_000)
        let cutoff = Date(timeIntervalSince1970: 1_699_999_000)
        let success = ProviderRefreshSnapshot.success(42, observedAt: observed, cutoff: cutoff)
        precondition(success.state.isUsable)
        precondition(success.value == 42)
        let refreshing = ProviderRefreshSnapshot<Int>.refreshing(retaining: success.value)
        precondition(refreshing.value == 42)
        let stale = refreshing.failed(observedAt: observed, cutoff: cutoff, error: "network")
        precondition(stale.value == 42)
        precondition(stale.state.isUsable)
        precondition(stale.state.errorMessage == "network")
        let unavailable = ProviderRefreshSnapshot<Int>(value: nil, state: .unavailable("not connected"))
        precondition(!unavailable.state.isUsable)
        print("PASS: provider refresh state retention checks")
    }
}
