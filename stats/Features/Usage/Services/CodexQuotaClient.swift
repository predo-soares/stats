import Foundation

/// Read-only boundary around credentials owned by Codex. Implementations must never renew,
/// replace, delete, or persist the credential they inspect.
protocol CodexCredentialReader: Sendable {
    func readCurrentCredential() throws -> CodexReadOnlyCredential?
}

struct CodexReadOnlyCredential: Sendable {
    /// A stable, non-secret account fingerprint. It may be derived from configured identity metadata.
    let accountIdentity: String
    /// Opaque credential material used only by the request transport; never retained by this client.
    let requestAuthorization: String
}

protocol CodexQuotaTransport: Sendable {
    func fetchQuota(credential: CodexReadOnlyCredential) async throws -> Data
}

/// The production reader/transport is intentionally introduced at the real-account checkpoint.
/// This safe default makes missing Codex-managed access explicit and never touches auth files.
struct UnavailableCodexCredentialReader: CodexCredentialReader {
    func readCurrentCredential() throws -> CodexReadOnlyCredential? { nil }
}

struct UnavailableCodexQuotaTransport: CodexQuotaTransport {
    func fetchQuota(credential: CodexReadOnlyCredential) async throws -> Data { throw CodexQuotaError.authenticationExpired }
}

struct CodexQuotaWindow: Sendable, Equatable, Identifiable {
    let id: String
    let name: String
    let remainingFraction: Double
    let resetsAt: Date?
}

struct CodexQuotaSnapshot: Sendable, Equatable {
    let accountIdentity: String
    let capturedAt: Date
    let windows: [CodexQuotaWindow]
}

enum CodexQuotaPublication: Sendable, Equatable {
    case authenticationMissing
    case authenticationExpired
    case awaitingIdentityConfirmation(previous: String?, pending: String)
    case unavailable(message: String, retained: CodexQuotaSnapshot?)
    case published(CodexQuotaSnapshot)
}

enum CodexQuotaError: LocalizedError, Sendable {
    case invalidResponse
    case authenticationExpired

    var errorDescription: String? {
        switch self {
        case .invalidResponse: "Codex returned quota data in an unsupported format."
        case .authenticationExpired: "Codex authentication expired. Renew it in Codex, then refresh this app."
        }
    }
}

struct CodexQuotaClient: Sendable {
    let credentialReader: any CodexCredentialReader
    let transport: any CodexQuotaTransport
    let now: @Sendable () -> Date

    init(
        credentialReader: any CodexCredentialReader,
        transport: any CodexQuotaTransport,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.credentialReader = credentialReader
        self.transport = transport
        self.now = now
    }

    /// Publishes quota data only for the already confirmed account identity. A changed identity
    /// cannot silently relabel an existing quota snapshot or local device activity.
    func refresh(
        confirmedIdentity: String?,
        retained: CodexQuotaSnapshot?
    ) async -> CodexQuotaPublication {
        let credential: CodexReadOnlyCredential?
        do {
            credential = try credentialReader.readCurrentCredential()
        } catch {
            return .unavailable(message: "Codex authentication could not be read.", retained: retained)
        }
        guard let credential else { return .authenticationMissing }
        guard confirmedIdentity == nil || confirmedIdentity == credential.accountIdentity else {
            return .awaitingIdentityConfirmation(previous: confirmedIdentity, pending: credential.accountIdentity)
        }
        do {
            let data = try await transport.fetchQuota(credential: credential)
            let snapshot = try parse(data, identity: credential.accountIdentity, capturedAt: now())
            return .published(snapshot)
        } catch CodexQuotaError.authenticationExpired {
            return .authenticationExpired
        } catch {
            return .unavailable(message: "Codex quota could not refresh.", retained: retained)
        }
    }

    /// Accepts the documented rate-limit shape while treating unknown/malformed windows as unavailable.
    /// No token total is inferred from a quota percentage.
    func parse(_ data: Data, identity: String, capturedAt: Date) throws -> CodexQuotaSnapshot {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw CodexQuotaError.invalidResponse }
        if let error = root["error"] as? [String: Any], let code = error["code"] as? String,
           ["invalid_api_key", "authentication_required", "token_expired"].contains(code) {
            throw CodexQuotaError.authenticationExpired
        }
        let limits = (root["rate_limit"] as? [String: Any]) ?? (root["rate_limits"] as? [String: Any]) ?? root
        let candidates: [(String, String)] = [("primary_window", "Session"), ("secondary_window", "Weekly")]
        let windows = try candidates.compactMap { key, name -> CodexQuotaWindow? in
            guard let window = limits[key] as? [String: Any] else { return nil }
            guard let used = number(window["used_percent"] ?? window["usedPercentage"]), used >= 0, used <= 100 else { throw CodexQuotaError.invalidResponse }
            let reset = date(window["reset_at"] ?? window["resets_at"])
            return CodexQuotaWindow(id: key, name: name, remainingFraction: (100 - used) / 100, resetsAt: reset)
        }
        guard !windows.isEmpty else { throw CodexQuotaError.invalidResponse }
        return CodexQuotaSnapshot(accountIdentity: identity, capturedAt: capturedAt, windows: windows)
    }

    private func number(_ value: Any?) -> Double? {
        if let number = value as? NSNumber { return number.doubleValue }
        if let string = value as? String { return Double(string) }
        return nil
    }

    private func date(_ value: Any?) -> Date? {
        if let seconds = number(value), seconds > 0 { return Date(timeIntervalSince1970: seconds) }
        guard let value = value as? String else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }
}
