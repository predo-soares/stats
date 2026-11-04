import Foundation

struct CursorQuotaWindow: Sendable, Equatable, Identifiable {
    let id: String
    let name: String
    let remainingFraction: Double
    let resetsAt: Date?
}

enum CursorQuotaPublication: Sendable, Equatable {
    case unavailable(String)
    case published([CursorQuotaWindow])
}

struct CursorQuotaClient: Sendable {
    func refresh(sessionToken: String) async -> CursorQuotaPublication {
        let parts = sessionToken.components(separatedBy: "%3A%3A")
        guard parts.count >= 2 else { return .unavailable("Cursor sign-in is missing or expired.") }
        let accessToken = parts.dropFirst().joined(separator: "%3A%3A")
        let primary = await refreshCurrentPeriod(accessToken: accessToken)
        if case .published = primary { return primary }

        if let summary = await refreshSummary(sessionToken: sessionToken), case .published = summary {
            return summary
        }

        if let requests = await refreshRequestUsage(sessionToken: sessionToken), case .published = requests {
            return requests
        }

        if case let .unavailable(message) = primary { return .unavailable(message) }
        return .unavailable("Cursor quota data is unavailable for this account.")
    }

    private func refreshCurrentPeriod(accessToken: String) async -> CursorQuotaPublication {
        var request = URLRequest(url: URL(string: "https://api2.cursor.sh/aiserver.v1.DashboardService/GetCurrentPeriodUsage")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("1", forHTTPHeaderField: "Connect-Protocol-Version")
        request.httpBody = Data("{}".utf8)
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return .unavailable("Cursor quota could not refresh.")
            }
            return try parse(data)
        } catch {
            return .unavailable("Cursor quota could not refresh.")
        }
    }

    private func refreshSummary(sessionToken: String) async -> CursorQuotaPublication? {
        var request = URLRequest(url: URL(string: "https://cursor.com/api/usage-summary")!)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("WorkosCursorSessionToken=\(sessionToken)", forHTTPHeaderField: "Cookie")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return nil }
            return try parseSummary(data)
        } catch {
            return nil
        }
    }

    private func refreshRequestUsage(sessionToken: String) async -> CursorQuotaPublication? {
        let parts = sessionToken.components(separatedBy: "%3A%3A")
        guard parts.count >= 2 else { return nil }
        let accessToken = parts.dropFirst().joined(separator: "%3A%3A")
        guard let subject = CursorCredential.accountID(from: accessToken) else { return nil }
        var components = URLComponents(string: "https://cursor.com/api/usage")
        components?.queryItems = [URLQueryItem(name: "user", value: subject)]
        guard let url = components?.url else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("WorkosCursorSessionToken=\(sessionToken)", forHTTPHeaderField: "Cookie")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return nil }
            return try parseRequestUsage(data)
        } catch {
            return nil
        }
    }

    func parse(_ data: Data) throws -> CursorQuotaPublication {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let plan = root["planUsage"] as? [String: Any]
        else { return .unavailable("Cursor quota data is unavailable for this account.") }

        let reset = number(root["billingCycleEnd"]).map { Date(timeIntervalSince1970: $0 / 1_000) }
        var windows: [CursorQuotaWindow] = []
        if let total = percentage(plan["totalPercentUsed"]) {
            windows.append(CursorQuotaWindow(id: "total", name: "Total usage", remainingFraction: 1 - total / 100, resetsAt: reset))
        }
        if let cursor = percentage(plan["autoPercentUsed"]) {
            windows.append(CursorQuotaWindow(id: "cursor-models", name: "Cursor models", remainingFraction: 1 - cursor / 100, resetsAt: reset))
        }
        if let other = percentage(plan["apiPercentUsed"]) {
            windows.append(CursorQuotaWindow(id: "other-models", name: "Other models", remainingFraction: 1 - other / 100, resetsAt: reset))
        }
        guard !windows.isEmpty else { return .unavailable("Cursor quota data is unavailable for this account.") }
        return .published(windows)
    }

    private func parseSummary(_ data: Data) throws -> CursorQuotaPublication {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .unavailable("Cursor summary data is unavailable for this account.")
        }
        let plan = ((root["individualUsage"] as? [String: Any])?["plan"] as? [String: Any])
            ?? (root["planUsage"] as? [String: Any])
        let reset = (root["billingCycleEnd"] as? String).flatMap(Self.isoDate)
        var windows: [CursorQuotaWindow] = []
        if let total = percentage(plan?["totalPercentUsed"]) {
            windows.append(CursorQuotaWindow(id: "total", name: "Total usage", remainingFraction: 1 - total / 100, resetsAt: reset))
        }
        if let cursor = percentage(plan?["autoPercentUsed"]) {
            windows.append(CursorQuotaWindow(id: "cursor-models", name: "Cursor models", remainingFraction: 1 - cursor / 100, resetsAt: reset))
        }
        if let other = percentage(plan?["apiPercentUsed"]) {
            windows.append(CursorQuotaWindow(id: "other-models", name: "Other models", remainingFraction: 1 - other / 100, resetsAt: reset))
        }
        guard !windows.isEmpty else { return .unavailable("Cursor summary has no quota values for this account.") }
        return .published(windows)
    }

    private func parseRequestUsage(_ data: Data) throws -> CursorQuotaPublication {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let request = (root["gpt-4"] as? [String: Any]) ?? (root["gpt4"] as? [String: Any]),
              let limit = number(request["maxRequestUsage"]), limit > 0
        else { return .unavailable("Cursor request quota data is unavailable for this account.") }
        let used = number(request["numRequestsTotal"]) ?? number(request["numRequests"]) ?? 0
        let reset = (root["startOfMonth"] as? String).flatMap(Self.isoDate).flatMap {
            Calendar.current.date(byAdding: .month, value: 1, to: $0)
        }
        return .published([CursorQuotaWindow(
            id: "requests",
            name: "Requests",
            remainingFraction: max(0, min(1, 1 - used / limit)),
            resetsAt: reset)])
    }

    private func percentage(_ value: Any?) -> Double? {
        guard let value = number(value), value.isFinite, (0...100).contains(value) else { return nil }
        return value
    }

    private func number(_ value: Any?) -> Double? {
        if let number = value as? NSNumber { return number.doubleValue }
        if let string = value as? String { return Double(string) }
        return nil
    }

    nonisolated private static func isoDate(_ value: String) -> Date? {
        ISO8601DateFormatter().date(from: value)
    }
}
