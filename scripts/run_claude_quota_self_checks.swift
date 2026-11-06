import Foundation

@main
struct RunClaudeQuotaSelfChecks {
    static func main() {
        var failures: [String] = []
        let client = ClaudeQuotaClient(
            configURL: URL(fileURLWithPath: "/tmp/missing-claude.json"),
            credentialsURL: URL(fileURLWithPath: "/tmp/missing-claude-creds.json")
        )

        let cache = """
        {"cachedUsageUtilization":{"fetchedAtMs":1,"utilization":{"five_hour":{"utilization":25,"resets_at":"2026-11-06T12:00:00Z"},"seven_day":{"utilization":40,"resets_at":"2026-11-10T09:00:00Z"}}}}
        """.data(using: .utf8)!
        switch client.readCachedUtilization(from: cache) {
        case .published(let windows):
            if windows.count != 2 { failures.append("expected 2 cached windows") }
            if windows.count >= 1, abs(windows[0].remainingFraction - 0.75) >= 0.001 {
                failures.append("five_hour remaining \(windows[0].remainingFraction)")
            }
            if windows.count >= 2, abs(windows[1].remainingFraction - 0.60) >= 0.001 {
                failures.append("seven_day remaining \(windows[1].remainingFraction)")
            }
        default:
            failures.append("cached utilization failed")
        }

        let api = """
        {"five_hour":{"utilization":0.1,"resets_at":"2026-11-06T18:00:00Z"},"seven_day":{"utilization":0.5,"resets_at":"2026-11-12T00:00:00Z"}}
        """.data(using: .utf8)!
        switch client.parseOAuthUsage(api) {
        case .published(let windows):
            if windows.count != 2 { failures.append("expected 2 oauth windows") }
            if windows.count >= 1, abs(windows[0].remainingFraction - 0.9) >= 0.001 {
                failures.append("oauth five_hour remaining \(windows[0].remainingFraction)")
            }
        default:
            failures.append("oauth parse failed")
        }

        if failures.isEmpty {
            print("PASS: Claude quota parse checks")
        } else {
            failures.forEach { print("FAIL: \($0)") }
            exit(1)
        }
    }
}
