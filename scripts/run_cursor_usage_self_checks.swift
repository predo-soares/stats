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
        await checkUnavailableEventsAreNotZero(failures: &failures)
        await checkIncompletePageFails(failures: &failures)
        await checkMalformedCountersFail(failures: &failures)

        if failures.isEmpty {
            print("PASS: Cursor usage parser and pagination checks")
        } else {
            failures.forEach { print("FAIL: \($0)") }
            exit(1)
        }
    }

    private static func checkUnavailableEventsAreNotZero(failures: inout [String]) async {
        let client = CursorUsageClient(transport: FixtureTransport(pages: [1: Data("{}".utf8)]))
        do {
            _ = try await client.fetchToday(sessionToken: "fixture")
            failures.append("unavailable Cursor event history was accepted as zero usage")
        } catch CursorUsageClientError.usageEventsUnavailable { }
        catch { failures.append("unavailable Cursor event history returned the wrong error") }
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

    private static func fixture(total: Int, events: [[String: Any]]) -> Data {
        try! JSONSerialization.data(withJSONObject: ["totalUsageEventsCount": total, "usageEventsDisplay": events])
    }

    private static func event(timestamp: Double, model: String, input: Int, cacheRead: Int, cacheWrite: Int, output: Int) -> [String: Any] {
        ["timestamp": timestamp, "model": model, "tokenUsage": ["inputTokens": input, "cacheReadTokens": cacheRead, "cacheWriteTokens": cacheWrite, "outputTokens": output]]
    }
}
