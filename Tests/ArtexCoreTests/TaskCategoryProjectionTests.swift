import XCTest
@testable import ArtexCore

final class TaskCategoryProjectionTests: XCTestCase {
    private func fixture() throws -> [String:Any] {
        let url = try XCTUnwrap(Bundle.module.url(forResource:"task-contract",withExtension:"json",subdirectory:"Fixtures"))
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with:Data(contentsOf:url)) as? [String:Any]); return try XCTUnwrap(root["task"] as? [String:Any])
    }
    private func category(_ name: String = "name") throws -> TaskCategoryRecord {
        try BackendJSONCoding.decode(TaskCategoryRecord.self,from:JSONSerialization.data(withJSONObject:["id":8,"name":name,"task_count":2,"created_at":"c","updated_at":"u"]))
    }
    @MainActor func testConfirmedCategoryProjectionKeepsTaskIdentityAndUnrelatedData() async throws {
        let api = ChatTestTransport(); var first = try fixture(); first["id"] = "7"; first["category_id"] = 8; first["category_name"] = "before"
        var second = first; second["id"] = "9"; second["category_id"] = NSNull(); second["category_name"] = NSNull()
        try api.enqueue(["tasks":[first,second],"active":"7"])
        let store = TaskStore(service:TaskService(client:api)); await store.refreshList()
        let original = try XCTUnwrap(store.list.value?.first)
        let ticket = try XCTUnwrap(store.beginCategoryMutation()); XCTAssertTrue(store.isMutating)
        store.finishCategoryMutation(ticket:ticket,change:.saved(try category("e\u{301} 中文 한국어")))
        let renamed = try XCTUnwrap(store.list.value?.first)
        XCTAssertEqual(renamed.categoryName,"e\u{301} 中文 한국어"); XCTAssertEqual(renamed.description,original.description); XCTAssertEqual(renamed.status,original.status)
        XCTAssertEqual(renamed.tokens,original.tokens); XCTAssertEqual(store.activeID,"7"); XCTAssertFalse(store.isMutating)
        let deletion = try XCTUnwrap(store.beginCategoryMutation()); store.finishCategoryMutation(ticket:deletion,change:.deleted(8))
        XCTAssertNil(store.list.value?.first?.categoryId); XCTAssertEqual(store.list.value?.count,2); XCTAssertEqual(store.activeID,"7")
        let tasks = [original,try BackendJSONCoding.decode(TaskRecord.self,from:JSONSerialization.data(withJSONObject:second))]
        XCTAssertEqual(TaskPresentation.rows(tasks,query:"",status:nil,category:.uncategorized,sort:.id,ascending:false,now:0).map(\.id),["9"])
        XCTAssertEqual(TaskPresentation.rows(tasks,query:"",status:nil,category:.category(8),sort:.id,ascending:false,now:0).map(\.id),["7"])
    }
    @MainActor func testOldResetReceiptAndPreexistingReadCannotOverwriteCategoryResult() async throws {
        let api = ChatTestTransport(); let store = TaskStore(service:TaskService(client:api))
        var continuation: CheckedContinuation<BackendHTTPResponse,Error>?
        api.handler = { _ in try await withCheckedThrowingContinuation { continuation = $0 } }
        let pending = Task { await store.refreshList() }
        for _ in 0..<1000 { if continuation != nil { break }; await Task.yield() }
        let ticket = try XCTUnwrap(store.beginCategoryMutation())
        store.finishCategoryMutation(ticket:ticket,change:.deleted(8))
        continuation?.resume(returning:try ChatTestTransport.response(["tasks":[fixture()],"active":""]))
        await pending.value; XCTAssertNil(store.list.value)
        let old = try XCTUnwrap(store.beginCategoryMutation()); store.reset(); XCTAssertTrue(store.isMutating)
        store.finishCategoryMutation(ticket:old,change:.saved(try category())); XCTAssertNil(store.list.value); XCTAssertFalse(store.isMutating)
        let final = try XCTUnwrap(store.beginCategoryMutation()); XCTAssertNil(store.beginCategoryMutation())
        store.finishCategoryMutation(ticket:final,change:nil)
    }
    func testSingleAndPartialBatchProjectionOnlyChangesConfirmedGrouping() throws {
        var raw = try fixture(); raw["id"] = "7"; raw["category_id"] = 8; raw["category_name"] = "before"
        let first = try BackendJSONCoding.decode(TaskRecord.self,from:JSONSerialization.data(withJSONObject:raw))
        raw["id"] = "9"; let second = try BackendJSONCoding.decode(TaskRecord.self,from:JSONSerialization.data(withJSONObject:raw))
        raw["id"] = "7"; raw["category_id"] = NSNull(); raw["category_name"] = NSNull()
        let cleared = try BackendJSONCoding.decode(TaskRecord.self,from:JSONSerialization.data(withJSONObject:raw))
        let single = TaskCategoryChange.assigned(cleared).applying(to:[first,second])
        XCTAssertNil(single[0].categoryId); XCTAssertEqual(single[1],second); XCTAssertEqual(single[0].status,first.status)
        let partial = try BackendJSONCoding.decode(TaskCategoryBatchResult.self,from:Data(#"{"items":[{"id":"7","ok":true},{"id":"9","ok":false}],"category":{"id":10,"name":"target","task_count":1,"created_at":"c","updated_at":"u"}}"#.utf8))
        let projected = TaskCategoryChange.batchAssigned(partial).applying(to:[first,second])
        XCTAssertEqual(projected[0].categoryId,10); XCTAssertEqual(projected[1],second); XCTAssertEqual(projected[0].tokens,first.tokens)
        let allFailed = try BackendJSONCoding.decode(TaskCategoryBatchResult.self,from:Data(#"{"items":[{"id":"7","ok":false}],"category":null}"#.utf8))
        XCTAssertEqual(TaskCategoryChange.batchAssigned(allFailed).applying(to:[first]),[first])
    }

}
