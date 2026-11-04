import Foundation

private struct FixtureCredentialReader: CodexCredentialReader {
    var credential: CodexReadOnlyCredential?
    var error: Error?

    func readCurrentCredential() throws -> CodexReadOnlyCredential? {
        if let error { throw error }
        return credential
    }
}

private final class FixtureQuotaTransport: CodexQuotaTransport, @unchecked Sendable {
    var bodies: [Data]
    var error: Error?
    private(set) var fetchCount = 0

    init(bodies: [Data], error: Error? = nil) {
        self.bodies = bodies
        self.error = error
    }

    func fetchQuota(credential: CodexReadOnlyCredential) async throws -> Data {
        fetchCount += 1
        if let error { throw error }
        guard !bodies.isEmpty else { throw CodexQuotaError.invalidResponse }
        return bodies.removeFirst()
    }
}

@main
struct RunCodexQuotaSelfChecks {
    static func main() async {
        var failures: [String] = []
        await checkMissingAuthentication(failures: &failures)
        await checkExpiredAuthentication(failures: &failures)
        await checkIdentityChangePausesPublication(failures: &failures)
        await checkFailedRequestRetainsSnapshot(failures: &failures)
        checkParseDoesNotInventTokenTotals(failures: &failures)

        if failures.isEmpty {
            print("PASS: Codex quota lifecycle checks")
        } else {
            failures.forEach { print("FAIL: \($0)") }
            exit(1)
        }
    }

    private static func checkMissingAuthentication(failures: inout [String]) async {
        let client = CodexQuotaClient(
            credentialReader: FixtureCredentialReader(credential: nil),
            transport: FixtureQuotaTransport(bodies: []),
            now: { Date(timeIntervalSince1970: 1) }
        )
        let publication = await client.refresh(confirmedIdentity: nil, retained: nil)
        guard case .authenticationMissing = publication else {
            failures.append("missing Codex auth was not published as authenticationMissing")
            return
        }
    }

    private static func checkExpiredAuthentication(failures: inout [String]) async {
        let client = CodexQuotaClient(
            credentialReader: FixtureCredentialReader(
                credential: CodexReadOnlyCredential(accountIdentity: "acct-a", requestAuthorization: "token")
            ),
            transport: FixtureQuotaTransport(bodies: [], error: CodexQuotaError.authenticationExpired),
            now: { Date(timeIntervalSince1970: 1) }
        )
        let publication = await client.refresh(confirmedIdentity: "acct-a", retained: nil)
        guard case .authenticationExpired = publication else {
            failures.append("expired Codex auth was not published as authenticationExpired")
            return
        }
    }

    private static func checkIdentityChangePausesPublication(failures: inout [String]) async {
        let transport = FixtureQuotaTransport(bodies: [fixtureQuotaJSON()])
        let client = CodexQuotaClient(
            credentialReader: FixtureCredentialReader(
                credential: CodexReadOnlyCredential(accountIdentity: "acct-b", requestAuthorization: "token")
            ),
            transport: transport,
            now: { Date(timeIntervalSince1970: 10) }
        )
        let retained = CodexQuotaSnapshot(
            accountIdentity: "acct-a",
            capturedAt: Date(timeIntervalSince1970: 1),
            windows: [CodexQuotaWindow(id: "primary_window", name: "Session", remainingFraction: 0.5, resetsAt: nil)]
        )
        let publication = await client.refresh(confirmedIdentity: "acct-a", retained: retained)
        guard case let .awaitingIdentityConfirmation(previous, pending) = publication else {
            failures.append("changed Codex identity did not pause quota publication")
            return
        }
        guard previous == "acct-a", pending == "acct-b", transport.fetchCount == 0 else {
            failures.append("identity change fetched quota before confirmation or lost identities")
            return
        }
    }

    private static func checkFailedRequestRetainsSnapshot(failures: inout [String]) async {
        let retained = CodexQuotaSnapshot(
            accountIdentity: "acct-a",
            capturedAt: Date(timeIntervalSince1970: 1),
            windows: [CodexQuotaWindow(id: "primary_window", name: "Session", remainingFraction: 0.4, resetsAt: nil)]
        )
        let client = CodexQuotaClient(
            credentialReader: FixtureCredentialReader(
                credential: CodexReadOnlyCredential(accountIdentity: "acct-a", requestAuthorization: "token")
            ),
            transport: FixtureQuotaTransport(bodies: [], error: CodexQuotaError.invalidResponse),
            now: { Date(timeIntervalSince1970: 10) }
        )
        let publication = await client.refresh(confirmedIdentity: "acct-a", retained: retained)
        guard case let .unavailable(_, kept) = publication, kept == retained else {
            failures.append("failed Codex quota refresh dropped the retained snapshot")
            return
        }
    }

    private static func checkParseDoesNotInventTokenTotals(failures: inout [String]) {
        let client = CodexQuotaClient(
            credentialReader: FixtureCredentialReader(credential: nil),
            transport: FixtureQuotaTransport(bodies: []),
            now: { Date(timeIntervalSince1970: 1) }
        )
        do {
            let snapshot = try client.parse(fixtureQuotaJSON(), identity: "acct-a", capturedAt: Date(timeIntervalSince1970: 1))
            guard snapshot.windows.count == 2,
                  snapshot.windows[0].remainingFraction == 0.75,
                  snapshot.windows[1].remainingFraction == 0.4
            else {
                failures.append("quota parse did not map remaining fractions from used_percent")
                return
            }
        } catch {
            failures.append("quota parse failed: \(error)")
        }
    }

    private static func fixtureQuotaJSON() -> Data {
        Data(#"""
        {"rate_limit":{"primary_window":{"used_percent":25,"reset_at":1700000800},"secondary_window":{"used_percent":60,"reset_at":1700000900}}}
        """#.utf8)
    }
}
