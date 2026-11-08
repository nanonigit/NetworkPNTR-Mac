import Foundation
import XCTest
@testable import ArtexCore

final class LLMRecordServiceTests: XCTestCase {
    private static let largeID: Int64 = 9_007_199_254_740_993

    private static func record(id: Int64 = largeID) -> [String: Any] {
        [
            "id": id, "ts": "2026-11-08T00:00:00Z", "model": "model+a", "profile_name": "",
            "session_id": "session日本語", "task_id": "task%1", "worker": "",
            "latency_ms": 0, "input_tokens": 10, "output_tokens": 20,
            "cache_read": 1, "cache_write": 2, "status": "ok"
        ]
    }

    @MainActor func testFiltersAndLazyDetailPreserveWireValuesAndOriginalText() async throws {
        let client = ChatTestTransport()
        let service = LLMRecordService(client: client)
        try client.enqueue(["records": [Self.record()], "total": 26])
        var row = Self.record()
        let raw = "data: 日本語\r\n\r\n"
        row["raw_response"] = raw
        row["request_body"] = "  {\"a\":1}\n"
        try client.enqueue(row)
        let list = try await service.list(filter: .init(model: "model+a", session: "  日本語+ ", task: "task%1"), page: 1, size: 25)
        XCTAssertEqual(list.records.first?.id, Self.largeID)
        XCTAssertEqual(list.records.first?.cacheWrite, 2)
        let detail = try await service.detail(id: Self.largeID)
        XCTAssertEqual(detail.rawResponse, raw)
        XCTAssertEqual(detail.requestBody, "  {\"a\":1}\n")
        XCTAssertNil(detail.rawRequest)
        XCTAssertEqual(client.calls.map(\.path), [
            "/api/llm/records?page=1&size=25&model=model%2Ba&session=%E6%97%A5%E6%9C%AC%E8%AA%9E%2B&task=task%251",
            "/api/llm/records/9007199254740993"
        ])
        XCTAssertTrue(client.calls.allSatisfy { $0.method == "GET" && $0.body == nil })
    }

    @MainActor func testNullTaskListAndLegacyDetailsAreAccepted() async throws {
        let client = ChatTestTransport()
        let service = LLMRecordService(client: client)
        try client.enqueue(["tasks": NSNull()])
        try client.enqueue(["tasks": [["task_id": "task%1", "count": 1]]])
        try client.enqueue(Self.record())
        let empty = try await service.tasks()
        XCTAssertTrue(empty.isEmpty)
        let tasks = try await service.tasks()
        XCTAssertEqual(tasks.first?.taskId, "task%1")
        let detail = try await service.detail(id: Self.largeID)
        XCTAssertNil(detail.rawResponse)
        XCTAssertNil(detail.rawRequest)
        XCTAssertEqual(client.calls.prefix(2).map(\.path), Array(repeating: "/api/llm/records/tasks", count: 2))
    }

    @MainActor func testInvalidInputDoesNotDispatchAndMismatchedDetailIsRejected() async throws {
        let client = ChatTestTransport()
        let service = LLMRecordService(client: client)
        do {
            _ = try await service.list(page: Int64.max)
            XCTFail("An overflowing offset must be rejected")
        } catch LLMRecordQueryError.invalidQuery {}
        do {
            _ = try await service.detail(id: 0)
            XCTFail("A zero record ID must be rejected")
        } catch LLMRecordQueryError.invalidQuery {}
        XCTAssertTrue(client.calls.isEmpty)
        try client.enqueue(Self.record(id: 2))
        do {
            _ = try await service.detail(id: 1)
            XCTFail("A mismatched record must be rejected")
        } catch BackendAPIError.invalidResponse {}
        try client.enqueue(["error": "unavailable"], status: 500)
        do {
            _ = try await service.tasks()
            XCTFail("A guest error must remain distinct from an empty task list")
        } catch BackendAPIError.status(500) {}
    }

    @MainActor func testCancelledDetailDoesNotReturnPayload() async throws {
        let client = ChatTestTransport()
        client.handler = { _ in
            withUnsafeCurrentTask { $0?.cancel() }
            var row = Self.record()
            row["raw_response"] = "discard this fixture"
            return try ChatTestTransport.response(row)
        }
        let service = LLMRecordService(client: client)
        let operation = Task { try await service.detail(id: Self.largeID) }
        do {
            _ = try await operation.value
            XCTFail("A cancelled detail must not return its payload")
        } catch is CancellationError {}
        XCTAssertEqual(client.calls.count, 1)
    }


    @MainActor func testRecordingWritesOnlyItsFieldAndUsesIndependentReadback() async throws {
        let client = ChatTestTransport()
        let service = LLMRecordService(client: client)
        try client.enqueue(["llm_record": true])
        try client.enqueue(["llm_record": false])
        let actual = try await service.setRecording(true)
        XCTAssertFalse(actual)
        XCTAssertEqual(client.calls.map(\.method), ["PUT", "GET"])
        XCTAssertEqual(client.calls.map(\.path), ["/api/settings", "/api/settings"])
        let body = try XCTUnwrap(client.calls.first?.body)
        XCTAssertEqual(try JSONSerialization.jsonObject(with: body) as? [String: Bool], ["llm_record": true])
    }

    @MainActor func testTaskDeletionCannotRetargetWhitespaceAndEscapesExactID() async throws {
        let client = ChatTestTransport()
        let service = LLMRecordService(client: client)
        for target in ["", "task ", "\u{0085}task", "task\0"] {
            do {
                _ = try await service.delete(task: target)
                XCTFail("Unsafe target was accepted")
            } catch LLMRecordQueryError.invalidQuery {}
        }
        XCTAssertTrue(client.calls.isEmpty)
        try client.enqueue(["deleted": 3])
        let count = try await service.delete(task: "task+%&")
        XCTAssertEqual(count, 3)
        XCTAssertEqual(client.calls.first?.path, "/api/llm/records?task=task%2B%25%26")
        XCTAssertEqual(client.calls.first?.method, "DELETE")
        XCTAssertNil(client.calls.first?.body)
    }

}
