import Foundation

struct ClaudeQuotaWindow: Sendable, Equatable, Identifiable {
    let id: String
    let name: String
    let remainingFraction: Double
    let resetsAt: Date?
}

enum ClaudeQuotaPublication: Sendable, Equatable {
    case unavailable(String)
    case published([ClaudeQuotaWindow])
}

/// Reads Claude Code rate-limit utilization without retaining OAuth tokens or raw credentials.
struct ClaudeQuotaClient: Sendable {
    let configURL: URL
    let credentialsURL: URL
    let session: URLSession

    init(
        configURL: URL = FileManager.default.homeDirectoryForCurrentUser.appending(path: ".claude.json"),
        credentialsURL: URL = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: ".claude/.credentials.json"),
        session: URLSession = .shared
    ) {
        self.configURL = configURL
        self.credentialsURL = credentialsURL
        self.session = session
    }

    func refresh() async -> ClaudeQuotaPublication {
        if let cached = readCachedUtilization() {
            return cached
        }
        return await refreshFromOAuth()
    }

    /// Parses Claude Code's `cachedUsageUtilization` snapshot from `~/.claude.json`.
    func readCachedUtilization(from data: Data? = nil) -> ClaudeQuotaPublication? {
        let payload: Data
        if let data {
            payload = data
        } else {
            guard let file = try? Data(contentsOf: configURL) else { return nil }
            payload = file
        }
        guard let root = try? JSONSerialization.jsonObject(with: payload) as? [String: Any],
              let cached = root["cachedUsageUtilization"] as? [String: Any]
        else { return nil }
        let utilization = (cached["utilization"] as? [String: Any]) ?? cached
        return windows(from: utilization)
    }

    func parseOAuthUsage(_ data: Data) -> ClaudeQuotaPublication {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .unavailable("Claude usage limits could not be parsed.")
        }
        let utilization = (root["utilization"] as? [String: Any]) ?? root
        return windows(from: utilization) ?? .unavailable("Claude usage limits were empty for this account.")
    }

    private func refreshFromOAuth() async -> ClaudeQuotaPublication {
        guard let token = loadAccessToken() else {
            return .unavailable("Claude usage limits need a Claude Code sign-in on this Mac.")
        }
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return .unavailable("Claude usage limits could not refresh.")
            }
            guard (200..<300).contains(http.statusCode) else {
                if http.statusCode == 401 || http.statusCode == 403 {
                    return .unavailable("Claude sign-in expired. Open Claude Code once, then refresh.")
                }
                return .unavailable("Claude usage limits could not refresh.")
            }
            return parseOAuthUsage(data)
        } catch {
            return .unavailable("Claude usage limits could not refresh.")
        }
    }

    private func loadAccessToken() -> String? {
        guard let data = try? Data(contentsOf: credentialsURL),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = root["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String,
              !token.isEmpty
        else { return nil }
        return token
    }

    private func windows(from utilization: [String: Any]) -> ClaudeQuotaPublication? {
        var windows: [ClaudeQuotaWindow] = []
        if let five = window(
            id: "five-hour",
            name: "Session",
            object: utilization["five_hour"] as? [String: Any] ?? utilization["fiveHour"] as? [String: Any]
        ) {
            windows.append(five)
        }
        if let seven = window(
            id: "seven-day",
            name: "Weekly",
            object: utilization["seven_day"] as? [String: Any] ?? utilization["sevenDay"] as? [String: Any]
        ) {
            windows.append(seven)
        }
        // Alternate Claude Code cache shape: `limits: [{kind,percent,resets_at}]`
        if windows.isEmpty, let limits = utilization["limits"] as? [[String: Any]] {
            for limit in limits {
                let kind = (limit["kind"] as? String)?.lowercased() ?? ""
                let percent = number(limit["percent"]) ?? number(limit["utilization"])
                guard let percent else { continue }
                let id: String
                let name: String
                switch kind {
                case "session", "five_hour", "five-hour":
                    id = "five-hour"; name = "Session"
                case "weekly_all", "weekly", "seven_day", "seven-day":
                    id = "seven-day"; name = "Weekly"
                default:
                    continue
                }
                windows.append(
                    ClaudeQuotaWindow(
                        id: id,
                        name: name,
                        remainingFraction: max(0, min(1, 1 - percent / 100)),
                        resetsAt: date(from: limit["resets_at"] ?? limit["resetsAt"])
                    )
                )
            }
        }
        return windows.isEmpty ? nil : .published(windows)
    }

    private func window(id: String, name: String, object: [String: Any]?) -> ClaudeQuotaWindow? {
        guard let object else { return nil }
        guard let used = number(object["utilization"]) ?? number(object["percent"]) else { return nil }
        // Values may be 0...1 or 0...100 depending on source.
        let percent = used <= 1.000_1 ? used * 100 : used
        return ClaudeQuotaWindow(
            id: id,
            name: name,
            remainingFraction: max(0, min(1, 1 - percent / 100)),
            resetsAt: date(from: object["resets_at"] ?? object["resetsAt"])
        )
    }

    private func number(_ value: Any?) -> Double? {
        if let value = value as? Double { return value }
        if let value = value as? Int { return Double(value) }
        return (value as? NSNumber)?.doubleValue
    }

    private func date(from value: Any?) -> Date? {
        if let value = value as? String {
            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return fractional.date(from: value) ?? ISO8601DateFormatter().date(from: value)
        }
        if let ms = number(value) {
            return Date(timeIntervalSince1970: ms > 10_000_000_000 ? ms / 1000 : ms)
        }
        return nil
    }
}
