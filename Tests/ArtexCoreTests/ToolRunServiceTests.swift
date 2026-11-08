import Foundation
import XCTest
@testable import ArtexCore

final class ToolRunServiceTests: XCTestCase {
    func testFilterEqualityPreservesDistinctWireBytes() {
        XCTAssertNotEqual(ToolRunFilter(keyword: "\u{E9}"), ToolRunFilter(keyword: "e\u{301}"))
        XCTAssertEqual(ToolRunFilter(keyword: "  keyword "), ToolRunFilter(keyword: "keyword"))
    }

    @MainActor func testTallyIdentityPreservesDistinctToolNameBytes() async throws {
        let api = ChatTestTransport()
        try api.enqueue(["stats": [
            ["tool": "\u{E9}", "total": 2, "errors": 0],
            ["tool": "e\u{301}", "total": 1, "errors": 0]
        ]])
        let rows = try await ToolRunService(client: api).stats()
        XCTAssertEqual(Set(rows.map(\.id)).count, 2)
    }

    @MainActor func testListAndStatsShareFiltersWithoutPaginatingStats() async throws {
        let api = ChatTestTransport()
        let service = ToolRunService(client: api)
        let explorationID: Int64 = 9_007_199_254_740_993
        let filter = ToolRunFilter(explorationID: explorationID, keyword: "  查 + %&  ")
        let input = "  {\"argument\":\"日本語\"}\n"
        try api.enqueue(["commands": [[
            "id": explorationID, "exploration_id": explorationID, "worker": "worker", "tool": "non_shell",
            "command": input, "output": "", "is_error": false, "created_at": "2026-11-08T00:00:00Z"
        ]], "total": 54])
        try api.enqueue(["stats": [["tool": "non_shell", "total": 54, "errors": 1]]])
        let page = try await service.list(filter: filter, page: 1, size: 25)
        let stats = try await service.stats(filter: filter)
        XCTAssertEqual(page.commands.first?.id, explorationID)
        XCTAssertEqual(page.commands.first?.command, input)
        XCTAssertEqual(page.commands.first?.output, "")
        XCTAssertEqual(page.total, 54)
        XCTAssertEqual(stats.first?.errors, 1)
        let suffix = "task=9007199254740993&q=%E6%9F%A5%20%2B%20%25%26"
        XCTAssertEqual(api.calls.map(\.path), [
            "/api/commands?page=1&size=25&" + suffix, "/api/commands/stats?" + suffix
        ])
        XCTAssertTrue(api.calls.allSatisfy { $0.method == "GET" && $0.body == nil })
    }

    @MainActor func testEmptyStatsAndHTTPFailureStayDistinct() async throws {
        let api = ChatTestTransport()
        let service = ToolRunService(client: api)
        try api.enqueue(["stats": []])
        let empty = try await service.stats()
        XCTAssertTrue(empty.isEmpty)
        try api.enqueue(["error": "guest error"], status: 500)
        do {
            _ = try await service.stats()
            XCTFail("Server failure should propagate")
        } catch BackendAPIError.status(500) {}
        XCTAssertEqual(api.calls.map(\.path), ["/api/commands/stats", "/api/commands/stats"])
    }

    @MainActor func testInvalidPageDoesNotDispatchAndMalformedCountsAreRejected() async throws {
        let api = ChatTestTransport()
        let service = ToolRunService(client: api)
        do {
            _ = try await service.list(page: Int64.max)
            XCTFail("Invalid offset should fail")
        } catch ToolRunQueryError.invalidQuery {}
        XCTAssertTrue(api.calls.isEmpty)
        try api.enqueue(["stats": [["tool": "fixture", "total": 1, "errors": 2]]])
        do {
            _ = try await service.stats()
            XCTFail("Malformed aggregate should fail")
        } catch BackendAPIError.invalidResponse {}
    }

    @MainActor func testCancellationAfterDispatchDiscardsTheReply() async throws {
        let api = ChatTestTransport()
        api.handler = { _ in
            withUnsafeCurrentTask { $0?.cancel() }
            return try ChatTestTransport.response(["stats": []])
        }
        let service = ToolRunService(client: api)
        let operation = Task { try await service.stats() }
        do {
            _ = try await operation.value
            XCTFail("A cancelled reply should not be delivered")
        } catch is CancellationError {}
        XCTAssertEqual(api.calls.count, 1)
    }
}
