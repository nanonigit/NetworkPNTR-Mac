import XCTest
@testable import NetworkPNTRCore

final class TaskBulkProjectionTests: XCTestCase {
    private func task(_ id: String = "7") throws -> [String:Any] {
        let url = try XCTUnwrap(Bundle.module.url(forResource:"task-contract",withExtension:"json",subdirectory:"Fixtures"))
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with:Data(contentsOf:url)) as? [String:Any]); var row = try XCTUnwrap(root["task"] as? [String:Any]); row["id"] = id; return row
    }
    @MainActor func testBulkGateProjectsOnlyConfirmedFieldsAndSharesCategoryExclusion() async throws {
        let api = ChatTestTransport(), store = TaskStore(service:TaskService(client:api))
        try api.enqueue(["tasks":[task(),task("8")],"active":"7"]); await store.refreshList()
        try api.enqueue(task()); await store.select(id:"7")
        let original = try XCTUnwrap(store.list.value?.first), token = try XCTUnwrap(store.beginBulkMutation())
        XCTAssertNil(store.beginCategoryMutation()); XCTAssertNil(store.beginBulkMutation())
        let blocked = await store.control(id:"7",action:.pause); if case .notStarted = blocked {} else { XCTFail("Mutual exclusion failed") }
        let items = try BackendJSONCoding.decode([TaskBatchControlItem].self,from:Data(#"[{"id":"7","ok":true,"status":"paused","queued":false},{"id":"8","ok":false}]"#.utf8))
        XCTAssertTrue(store.applyBulkChange(ticket:token,change:.controlled(items)))
        XCTAssertEqual(store.list.value?.first?.status,"paused"); XCTAssertEqual(store.list.value?.first?.description,original.description)
        XCTAssertEqual(store.detail.value?.status,"paused"); XCTAssertEqual(store.activeID,"7")
        let deleted = try BackendJSONCoding.decode(TaskDeletionResult.self,from:Data(#"{"deleted":"7","assets_deleted":0,"assets_detached":0,"traffic_deleted":0,"files_deleted":false,"findings_deleted":0,"llm_records_deleted":0}"#.utf8))
        XCTAssertTrue(store.applyBulkChange(ticket:token,change:.deleted(deleted)))
        XCTAssertNil(store.selectedID); XCTAssertNil(store.activeID); XCTAssertNil(store.detail.value); XCTAssertEqual(store.list.value?.map(\.id),["8"])
        store.finishBulkMutation(ticket:token); XCTAssertFalse(store.isMutating)
    }
    @MainActor func testResetRejectsOldBulkReceiptWithoutReleasingPendingGate() async throws {
        let api = ChatTestTransport(), store = TaskStore(service:TaskService(client:api))
        let token = try XCTUnwrap(store.beginBulkMutation()); store.reset()
        XCTAssertTrue(store.isMutating); XCTAssertNil(store.beginCategoryMutation())
        let result = try BackendJSONCoding.decode(TaskCategoryBatchResult.self,from:Data(#"{"items":[{"id":"7","ok":true}],"category":null}"#.utf8))
        XCTAssertFalse(store.applyBulkChange(ticket:token,change:.moved(result)))
        store.finishCategoryMutation(ticket:token,change:nil); XCTAssertTrue(store.isMutating)
        store.finishBulkMutation(ticket:token); XCTAssertFalse(store.isMutating); XCTAssertNil(store.list.value)
    }
    @MainActor func testBulkStartInvalidatesHeldReadAndMoveOnlyTouchesSuccessfulRows() async throws {
        let api = ChatTestTransport(), store = TaskStore(service:TaskService(client:api))
        try api.enqueue(["tasks":[task(),task("8")],"active":"7"]); await store.refreshList()
        var reply: CheckedContinuation<BackendHTTPResponse,Error>?
        api.handler = { _ in try await withCheckedThrowingContinuation { reply = $0 } }
        let read = Task { await store.refreshList() }
        for _ in 0..<10000 { if reply != nil { break }; await Task.yield() }
        let token = try XCTUnwrap(store.beginBulkMutation()), original = try XCTUnwrap(store.list.value?.last)
        let moved = try BackendJSONCoding.decode(TaskCategoryBatchResult.self,from:Data(#"{"items":[{"id":"7","ok":true},{"id":"8","ok":false}],"category":{"id":99,"name":"e\u0301 中文 한국어","task_count":1,"created_at":"c","updated_at":"u"}}"#.utf8))
        XCTAssertTrue(store.applyBulkChange(ticket:token,change:.moved(moved))); store.finishBulkMutation(ticket:token)
        reply?.resume(returning:try ChatTestTransport.response(["tasks":[],"active":""]))
        await read.value; XCTAssertEqual(store.list.value?.first?.categoryId,99); XCTAssertEqual(store.list.value?.last,original)
        XCTAssertFalse(store.applyBulkChange(ticket:UUID(),change:.moved(moved)))
    }
}
