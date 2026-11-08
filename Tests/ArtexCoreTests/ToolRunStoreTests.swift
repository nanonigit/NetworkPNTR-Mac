import Observation
import XCTest
@testable import ArtexCore

final class ToolRunStoreTests: XCTestCase {
    @MainActor func testPagingAndPageSizeRetainUnpaginatedStats() async throws {
        let api = ChatTestTransport()
        let store = ToolRunStore(service: ToolRunService(client: api))
        store.setFilter(.init(explorationID: 42, keyword: " fixture "))
        try api.enqueue(["stats": [["tool": "fixture", "total": 51, "errors": 1]]])
        try api.enqueue(["commands": [], "total": 51])
        try api.enqueue(["commands": [], "total": 51])
        await store.refreshStats()
        await store.refreshList()
        XCTAssertTrue(store.hasNext)
        XCTAssertTrue(store.setPage(1))
        XCTAssertNil(store.list.value)
        XCTAssertEqual(store.stats.value?.first?.total, 51)
        await store.refreshList()
        XCTAssertFalse(store.hasNext)
        XCTAssertTrue(store.hasPrevious)
        XCTAssertTrue(store.setPageSize(25))
        XCTAssertEqual(store.page, 0)
        XCTAssertEqual(store.stats.value?.first?.errors, 1)
        XCTAssertEqual(api.calls.map(\.path), [
            "/api/commands/stats?task=42&q=fixture",
            "/api/commands?page=0&size=50&task=42&q=fixture",
            "/api/commands?page=1&size=50&task=42&q=fixture"
        ])
    }

    @MainActor func testLateListAndStatsFromPreviousFilterCannotPublish() async throws {
        let api = ChatTestTransport()
        var oldList: CheckedContinuation<BackendHTTPResponse, any Error>?
        var oldStats: CheckedContinuation<BackendHTTPResponse, any Error>?
        api.handler = { call in
            if call.path.contains("q=old") {
                return try await withCheckedThrowingContinuation { continuation in
                    if call.path.hasPrefix("/api/commands/stats") { oldStats = continuation }
                    else { oldList = continuation }
                }
            }
            if call.path.hasPrefix("/api/commands/stats") {
                return try ChatTestTransport.response(["stats": [["tool": "new", "total": 2, "errors": 0]]])
            }
            return try ChatTestTransport.response(["commands": [], "total": 2])
        }
        let store = ToolRunStore(service: ToolRunService(client: api))
        store.setFilter(.init(keyword: "old"))
        XCTAssertTrue(store.setPage(1))
        let list = Task { await store.refreshList() }
        let stats = Task { await store.refreshStats() }
        for _ in 0..<10_000 {
            if oldList != nil && oldStats != nil { break }
            await Task.yield()
        }
        defer {
            oldList?.resume(throwing: CancellationError())
            oldStats?.resume(throwing: CancellationError())
            list.cancel()
            stats.cancel()
        }
        let listReply = try XCTUnwrap(oldList)
        let statsReply = try XCTUnwrap(oldStats)
        let staleResponse = try ChatTestTransport.response(["commands": [], "total": 99])
        store.setFilter(.init(keyword: "new"))
        XCTAssertEqual(store.page, 0)
        await store.refreshList()
        await store.refreshStats()
        oldList = nil
        oldStats = nil
        listReply.resume(returning: staleResponse)
        statsReply.resume(throwing: BackendAPIError.status(500))
        await list.value
        await stats.value
        XCTAssertEqual(store.list.value?.total, 2)
        XCTAssertEqual(store.stats.value?.first?.tool, "new")
        XCTAssertNil(store.stats.failure)
        XCTAssertFalse(store.list.isLoading)
        XCTAssertFalse(store.stats.isLoading)
    }

    @MainActor func testReopenedSummarySupersedesCancelledReadForSameFilter() async throws {
        let api = ChatTestTransport()
        var dismissedReply: CheckedContinuation<BackendHTTPResponse, any Error>?
        api.handler = { _ in
            if dismissedReply == nil {
                return try await withCheckedThrowingContinuation { dismissedReply = $0 }
            }
            return try ChatTestTransport.response(["stats": [["tool": "new", "total": 2, "errors": 0]]])
        }
        let store = ToolRunStore(service: ToolRunService(client: api))
        let dismissed = Task { await store.refreshStats() }
        for _ in 0..<10_000 {
            if dismissedReply != nil { break }
            await Task.yield()
        }
        defer {
            dismissed.cancel()
            dismissedReply?.resume(throwing: CancellationError())
        }
        let reply = try XCTUnwrap(dismissedReply)
        dismissed.cancel()
        await store.refreshStats()
        dismissedReply = nil
        reply.resume(throwing: CancellationError())
        await dismissed.value

        XCTAssertEqual(store.stats.value?.first?.tool, "new")
        XCTAssertFalse(store.stats.isLoading)
        XCTAssertNil(store.stats.failure)
    }

    @MainActor func testFilterChangeDuringPublicationDetachesOldResult() async throws {
        let api = ChatTestTransport()
        let store = ToolRunStore(service: ToolRunService(client: api))
        store.setFilter(.init(keyword: "old"))
        try api.enqueue(["commands": [], "total": 99])
        withObservationTracking {
            _ = store.list.value
        } onChange: {
            MainActor.assumeIsolated { store.setFilter(.init(keyword: "new")) }
        }
        await store.refreshList()
        XCTAssertEqual(store.filter.keyword, "new")
        XCTAssertNil(store.list.value)
        XCTAssertFalse(store.list.isLoading)
        try api.enqueue(["commands": [], "total": 2])
        await store.refreshList()
        XCTAssertEqual(store.list.value?.total, 2)
    }
}
