import Foundation

private struct FixtureTransport: CursorUsageTransport {
    let pages: [Int: Data]

    func page(sessionToken: String, start: Date, end: Date, page: Int, pageSize: Int) async throws -> Data {
        guard let page = pages[page] else { throw CursorUsageClientError.incompletePages }
        return page
    }
}

@main
struct RunCursorUsageSelfChecks {
    static func main() async {
        var failures: [String] = []
        await checkCompletePagination(failures: &failures)
        await checkEmptyEventsAreConfirmedEmpty(failures: &failures)
        await checkIncompletePageFails(failures: &failures)
        await checkMalformedCountersFail(failures: &failures)
        checkSummaryFallback(failures: &failures)

        if failures.isEmpty {
            print("PASS: Cursor usage parser and pagination checks")
        } else {
            failures.forEach { print("FAIL: \($0)") }
            exit(1)
        }
    }

    private static func checkEmptyEventsAreConfirmedEmpty(failures: inout [String]) async {
        let client = CursorUsageClient(transport: FixtureTransport(pages: [1: Data("{}".utf8)]))
        do {
            let events = try await client.fetchToday(sessionToken: "fixture")
            if !events.isEmpty { failures.append("empty Cursor event history returned records") }
        } catch { failures.append("empty Cursor event history was not accepted as an empty day") }
    }

    private static func checkCompletePagination(failures: inout [String]) async {
        let first = fixture(total: 2, events: [event(timestamp: 1_700_000_000_000, model: "model-a", input: 10, cacheRead: 2, cacheWrite: 3, output: 4)])
        let second = fixture(total: 2, events: [event(timestamp: 1_700_000_100_000, model: "model-b", input: 20, cacheRead: 5, cacheWrite: 7, output: 8)])
        let client = CursorUsageClient(transport: FixtureTransport(pages: [1: first, 2: second]))
        do {
            let events = try await client.fetchToday(sessionToken: "fixture", now: Date(timeIntervalSince1970: 1_700_000_200))
            let total = events.reduce(0) { $0 + $1.totalTokens }
            guard events.count == 2, total == 59, events[0].identifier != events[1].identifier else {
                failures.append("complete pages did not retain disjoint token buckets")
                return
            }
            let history = try await client.fetchHistory(sessionToken: "fixture", now: Date(timeIntervalSince1970: 1_700_000_200), days: 120)
            if history.count != 2 { failures.append("bounded history did not collect complete pagination") }
        } catch { failures.append("complete pages unexpectedly failed") }
    }

    private static func checkIncompletePageFails(failures: inout [String]) async {
        let page = fixture(total: 2, events: [])
        let client = CursorUsageClient(transport: FixtureTransport(pages: [1: page]))
        do {
            _ = try await client.fetchToday(sessionToken: "fixture")
            failures.append("incomplete page was accepted")
        } catch CursorUsageClientError.incompletePages { }
        catch { failures.append("incomplete page returned the wrong error") }
    }

    private static func checkMalformedCountersFail(failures: inout [String]) async {
        let page = fixture(total: 1, events: [event(timestamp: 1_700_000_000_000, model: "model-a", input: -1, cacheRead: 0, cacheWrite: 0, output: 1)])
        do {
            _ = try CursorUsageClient(transport: FixtureTransport(pages: [:])).parse(page)
            failures.append("negative token counter was accepted")
        } catch CursorUsageClientError.invalidResponse { }
        catch { failures.append("malformed counter returned the wrong error") }
    }

    private static func checkSummaryFallback(failures: inout [String]) {
        let data = Data(#"""
        {
            "billingCycleEnd":"2026-12-01T00:00:00Z",
            "individualUsage":{"plan":{"totalPercentUsed":49,"autoPercentUsed":25,"apiPercentUsed":100}}
        }
        """#.utf8)
        do {
            let publication = try CursorQuotaClient().parseSummary(data)
            guard case let .published(windows) = publication,
                  windows.map(\.id) == ["total", "cursor-models", "other-models"],
                  abs(windows[0].remainingFraction - 0.51) < 0.001
            else {
                failures.append("Cursor summary fallback did not publish expected quota windows")
                return
            }
        } catch {
            failures.append("Cursor summary fallback parsing failed")
        }
    }

    private static func fixture(total: Int, events: [[String: Any]]) -> Data {
        try! JSONSerialization.data(withJSONObject: ["totalUsageEventsCount": total, "usageEventsDisplay": events])
    }

    private static func event(timestamp: Double, model: String, input: Int, cacheRead: Int, cacheWrite: Int, output: Int) -> [String: Any] {
        ["timestamp": timestamp, "model": model, "tokenUsage": ["inputTokens": input, "cacheReadTokens": cacheRead, "cacheWriteTokens": cacheWrite, "outputTokens": output]]
    }
}
