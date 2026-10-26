import XCTest
@testable import ArtexCore

final class TaskArchiveGateTests: XCTestCase {
    @MainActor func testArchiveGateSharesTaskExclusionAndSurvivesReset() async throws {
        let api = ChatTestTransport(); let store = TaskStore(service:TaskService(client:api))
        let token = try XCTUnwrap(store.beginArchiveMutation()); XCTAssertTrue(store.isMutating)
        XCTAssertNil(store.beginCategoryMutation()); XCTAssertNil(store.beginBulkMutation()); XCTAssertNil(store.beginArchiveMutation())
        store.finishBulkMutation(ticket:token); store.finishCategoryMutation(ticket:token,change:nil); XCTAssertTrue(store.isMutating)
        store.reset(); XCTAssertNil(store.beginArchiveMutation()); store.finishArchiveMutation(ticket:UUID()); XCTAssertTrue(store.isMutating)
        store.finishArchiveMutation(ticket:token); XCTAssertFalse(store.isMutating); XCTAssertNil(store.list.value)
        let bulk = try XCTUnwrap(store.beginBulkMutation()); XCTAssertNil(store.beginArchiveMutation()); store.finishBulkMutation(ticket:bulk)
    }
    @MainActor func testArchiveReadGateInvalidatesReadsAndBlocksSelectionAndFiltersUntilTerminal() async throws {
        let api = ChatTestTransport(); let store = TaskArchiveStore(service:TaskArchiveService(client:api))
        var reply: CheckedContinuation<BackendHTTPResponse,Error>?
        api.handler = { _ in try await withCheckedThrowingContinuation { reply = $0 } }
        let read = Task { await store.refresh() }
        for _ in 0..<10000 { if reply != nil { break }; await Task.yield() }
        let gate = try XCTUnwrap(store.beginMutation()); XCTAssertTrue(store.isMutating)
        XCTAssertFalse(store.configure(page:2,size:20,query:"x",state:nil)); await store.select(9); XCTAssertNil(store.selectedID)
        await store.refresh(); await store.refreshSelected(); XCTAssertEqual(api.calls.count,1)
        try XCTUnwrap(reply).resume(returning:.init(status:200,body:Data(#"{"items":[],"total":0,"page":1,"size":20}"#.utf8)))
        await read.value; XCTAssertNil(store.list.value)
        store.reset(); XCTAssertTrue(store.isMutating); XCTAssertNil(store.beginMutation())
        store.finishMutation(ticket:UUID(),clearSelection:true); XCTAssertTrue(store.isMutating)
        store.finishMutation(ticket:gate,clearSelection:true); XCTAssertFalse(store.isMutating); XCTAssertTrue(store.list.isStale)
    }
}
