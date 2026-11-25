import XCTest
@testable import NetworkPNTRCore

@MainActor final class GuestLogServiceTests: XCTestCase {
    private func row(_ sequence: Int64, id: Int64? = nil, level: String = "info",
                     tag: String = "fixture", text: String = "Sample") -> [String: Any] {
        var row: [String: Any] = ["seq": sequence, "ts": "2026-11-25T01:00:00Z",
                                  "level": level, "tag": tag, "text": text]
        if let id { row["db_id"] = id }
        return row
    }

    func testRecentRetainsRestoredRingOrderAndExactCursor() async throws {
        let transport = ChatTestTransport()
        let service = GuestLogService(client: transport)
        let large: Int64 = 9_007_199_254_740_993
        try transport.enqueue(["items": [row(large, id: 7), row(large - 1)], "cursor": large])
        let page = try await service.recent(since: 0)
        XCTAssertEqual(page.items.map(\.seq), [large, large - 1])
        XCTAssertEqual(page.cursor, large)
        try transport.enqueue(["items": NSNull(), "cursor": large])
        let empty = try await service.recent(since: large)
        XCTAssertTrue(empty.items.isEmpty)
        XCTAssertEqual(transport.calls.map(\.path),
                       ["/api/logs?since=0&limit=1000", "/api/logs?since=9007199254740993&limit=1000"])
        XCTAssertTrue(transport.calls.allSatisfy { $0.method == "GET" && $0.body == nil })
    }

    func testHistoryRequiresAscendingDatabaseIDsBelowRequest() async throws {
        let transport = ChatTestTransport()
        let service = GuestLogService(client: transport)
        try transport.enqueue(["items": [row(0, id: 80), row(0, id: 81)], "has_more": false])
        let page = try await service.history(before: 82)
        XCTAssertEqual(page.items.map(\.dbId), [80, 81])
        XCTAssertEqual(transport.calls.first?.path, "/api/logs/history?before=82&limit=200")
        try transport.enqueue(["items": [row(0, id: 82)], "has_more": false])
        do {
            _ = try await service.history(before: 82)
            XCTFail("History included its exclusive boundary")
        } catch BackendAPIError.invalidResponse {}
        try transport.enqueue(["error": "private detail"], status: 500)
        do {
            _ = try await service.history(before: 82)
            XCTFail("History accepted an error response")
        } catch BackendAPIError.status(500) {}
    }

    func testClearDuringReadDropsLateRowsWithoutReplayingTheirCursor() async throws {
        let transport = ChatTestTransport()
        let store = GuestLogStore(service: GuestLogService(client: transport))
        let request = AsyncStream<Void>.makeStream()
        let release = AsyncStream<Void>.makeStream()
        let loaded = try ChatTestTransport.response(["items": [row(1, id: 3)], "cursor": 1])
        transport.handler = { _ in
            request.continuation.yield()
            for await _ in release.stream { break }
            return loaded
        }
        let pending = Task { await store.refresh() }
        var ready = request.stream.makeAsyncIterator()
        _ = await ready.next()
        store.clear()
        release.continuation.yield()
        await pending.value
        request.continuation.finish()
        release.continuation.finish()
        XCTAssertTrue(store.rows.isEmpty)

        transport.handler = nil
        try transport.enqueue(["items": [row(2, id: 4)], "cursor": 2])
        await store.refresh()
        XCTAssertEqual(transport.calls.last?.path, "/api/logs?since=1&limit=1000")
        XCTAssertEqual(store.rows.map(\.seq), [2])
    }

    func testStoreKeepsCursorOnClearAndDiscardsPausedRows() async throws {
        let transport = ChatTestTransport()
        let store = GuestLogStore(service: GuestLogService(client: transport))
        try transport.enqueue(["items": [row(1, id: 4)], "cursor": 1])
        await store.refresh()
        store.paused = true
        try transport.enqueue(["items": [row(2, id: 5)], "cursor": 2])
        await store.refresh()
        XCTAssertEqual(store.rows.map(\.seq), [1])
        store.clear()
        store.paused = false
        try transport.enqueue(["items": [row(3, id: 6, level: "warn", tag: "Fixture", text: "Plain <tag>")], "cursor": 3])
        await store.refresh()
        XCTAssertEqual(store.filtered(keyword: "FIXTURE", level: .warning).map(\.text), ["Plain <tag>"])
        XCTAssertEqual(transport.calls.last?.path, "/api/logs?since=2&limit=1000")
        try transport.enqueue(["items": [row(0, id: 4), row(0, id: 5)], "has_more": false])
        await store.loadOlder()
        XCTAssertEqual(store.rows.map(\.dbId), [4, 5, 6])
        XCTAssertFalse(store.canLoadOlder)
    }
}
