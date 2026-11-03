import Foundation

/// Reads only the existing Codex auth file. It never rewrites, refreshes, or persists its contents.
struct LocalCodexCredentialReader: CodexCredentialReader {
    let authURL: URL

    init(environment: [String: String] = ProcessInfo.processInfo.environment) {
        let root = environment["CODEX_HOME"].flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0, isDirectory: true) }
            ?? FileManager.default.homeDirectoryForCurrentUser.appending(path: ".codex", directoryHint: .isDirectory)
        self.authURL = root.appending(path: "auth.json")
    }

    func readCurrentCredential() throws -> CodexReadOnlyCredential? {
        guard FileManager.default.fileExists(atPath: authURL.path) else { return nil }
        let data = try Data(contentsOf: authURL, options: [.mappedIfSafe])
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tokens = root["tokens"] as? [String: Any],
              let access = string(tokens["access_token"] ?? tokens["accessToken"]),
              let account = string(tokens["account_id"] ?? tokens["accountId"]),
              !access.isEmpty, !account.isEmpty else { return nil }
        if let expiration = jwtExpiration(access), expiration <= .now { throw CodexQuotaError.authenticationExpired }
        return CodexReadOnlyCredential(accountIdentity: account, requestAuthorization: access)
    }

    private func string(_ value: Any?) -> String? { (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func jwtExpiration(_ token: String) -> Date? {
        let parts = token.split(separator: ".")
        guard parts.count > 1 else { return nil }
        var payload = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)
        guard let data = Data(base64Encoded: payload), let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let seconds = object["exp"] as? NSNumber else { return nil }
        return Date(timeIntervalSince1970: seconds.doubleValue)
    }
}

struct ChatGPTCodexQuotaTransport: CodexQuotaTransport {
    func fetchQuota(credential: CodexReadOnlyCredential) async throws -> Data {
        var request = URLRequest(url: URL(string: "https://chatgpt.com/backend-api/wham/usage")!, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        request.httpMethod = "GET"
        request.setValue("Bearer \(credential.requestAuthorization)", forHTTPHeaderField: "Authorization")
        request.setValue(credential.accountIdentity, forHTTPHeaderField: "ChatGPT-Account-Id")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("stats", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw CodexQuotaError.invalidResponse }
        if http.statusCode == 401 { throw CodexQuotaError.authenticationExpired }
        guard (200..<300).contains(http.statusCode) else { throw CodexQuotaError.invalidResponse }
        return data
    }
}
