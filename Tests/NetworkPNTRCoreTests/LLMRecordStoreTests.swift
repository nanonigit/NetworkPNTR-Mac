import Foundation
import XCTest
@testable import NetworkPNTRCore

final class LLMRecordStoreTests: XCTestCase {
    @MainActor func testFilterChangesResetPaginationAndDiscardThePreviousQuery() async throws {
        let client = ChatTestTransport()
        let store = LLMRecordStore(service: LLMRecordService(client: client))
        store.setPage(2)
        client.handler = { call in
            if call.path.contains("page=2") {
                store.apply(.init(model: "new"))
                return try ChatTestTransport.response(["records": [], "total": 127])
            }
            return try ChatTestTransport.response(["records": [], "total": 0])
        }
        await store.refresh()
        XCTAssertEqual(store.page, 0)
        XCTAssertNil(store.list.value)
        await store.refresh()
        XCTAssertEqual(store.list.value?.total, 0)
        XCTAssertFalse(store.hasNext)
        XCTAssertEqual(client.calls.map(\.path), [
            "/api/llm/records?page=2&size=50",
            "/api/llm/records?page=0&size=50&model=new"
        ])
    }

    @MainActor func testReopenedDetailDoesNotInheritAnEarlierFailure() async throws {
        let client = ChatTestTransport()
        let store = LLMRecordStore(service: LLMRecordService(client: client))
        try client.enqueue(["error": "missing"], status: 404)
        let first = store.detailState()
        await store.loadDetail(id: 7, into: first)
        XCTAssertNotNil(first.failure)
        let reopened = store.detailState()
        XCTAssertNil(reopened.failure)
        XCTAssertNil(reopened.value)
    }

    @MainActor func testFailedDeleteInvalidatesCachedRowsAndTaskTargets() async throws {
        let client = ChatTestTransport()
        let store = LLMRecordStore(service: LLMRecordService(client: client))
        try client.enqueue(["tasks": [["task_id": "selected", "count": 3]]])
        await store.refreshTasks()
        try client.enqueue(["records": [], "total": 0])
        await store.refresh()
        try client.enqueue(["error": "unavailable"], status: 500)
        let deleted = await store.delete(task: "selected")
        XCTAssertFalse(deleted)
        XCTAssertNotNil(store.mutationFailure)
        XCTAssertNil(store.list.value)
        XCTAssertTrue(store.tasks.isStale)
        let repeated = await store.delete(task: "selected")
        XCTAssertFalse(repeated)
        XCTAssertEqual(client.calls.map(\.method), ["GET", "GET", "DELETE"])
    }

}
