import Foundation

private struct FixtureTransport: CursorUsageTransport {
    let pages: [Data]

    func page(sessionToken: String, start: Date, end: Date, page: Int, pageSize: Int) async throws -> Data {
        guard pages.indices.contains(page - 1) else { throw CursorUsageClientError.incompletePages }
        return pages[page - 1]
    }
}

@main
private struct CursorUsageFixtureCheck {
    static func main() async throws {
        let pages = [
            Data("{\"totalUsageEventsCount\":2,\"usageEventsDisplay\":[{\"timestamp\":1793750400000,\"model\":\"gpt-5\",\"tokenUsage\":{\"inputTokens\":10,\"cacheReadTokens\":2,\"cacheWriteTokens\":3,\"outputTokens\":5}}]}".utf8),
            Data("{\"totalUsageEventsCount\":2,\"usageEventsDisplay\":[{\"timestamp\":1793750460000,\"model\":\"gpt-5\",\"tokenUsage\":{\"inputTokens\":20,\"cacheReadTokens\":4,\"cacheWriteTokens\":6,\"outputTokens\":10}}]}".utf8)
        ]
        let client = CursorUsageClient(transport: FixtureTransport(pages: pages))
        let events = try await client.fetch(
            sessionToken: "fixture",
            start: Date(timeIntervalSince1970: 1_793_750_400),
            end: Date(timeIntervalSince1970: 1_793_750_500),
            pageSize: 1
        )
        precondition(events.count == 2)
        precondition(events.map(\.totalTokens) == [20, 40])
        print("Cursor usage fixture check passed: \(events.count) paginated events")
    }
}
