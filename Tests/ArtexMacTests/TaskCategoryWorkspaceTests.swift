import XCTest
@testable import ArtexCore
@testable import ArtexMac

@MainActor private final class CategoryWorkspaceAPI: BackendJSONTransport {
    var calls: [(String,String,Data?)] = []
    var hold = false
    var holdReads = false
    var status = 200
    var pending: [CheckedContinuation<BackendHTTPResponse,Error>] = []
    var reads: [String:CheckedContinuation<BackendHTTPResponse,Error>] = [:]
    func row(_ id: Int64 = 8) -> [String:Any] { ["id":id,"name":"category \(id)","task_count":0,"created_at":"c","updated_at":"u"] }
    func response(_ value: Any, status: Int = 200) throws -> BackendHTTPResponse { .init(status:status,body:try JSONSerialization.data(withJSONObject:value)) }
    func send(method: String,path: String,body: Data?,bearer: String?) async throws -> BackendHTTPResponse {
        calls.append((method,path,body))
        if method == "GET" {
            if holdReads { return try await withCheckedThrowingContinuation { reads[path] = $0 } }
            if path == "/api/task-categories" { return try response(["categories":[row(8),row(9)]]) }
            return try response(["tasks":[],"active":""])
        }
        if hold { return try await withCheckedThrowingContinuation { pending.append($0) } }
        if status != 200 { return try response(["error":"private error"],status:status) }
        if method == "DELETE" { return try response(["deleted":8]) }
        return try response(row(method == "POST" ? 10 : 8),status:method == "POST" ? 201 : 200)
    }
}

final class TaskCategoryWorkspaceTests: XCTestCase {
    @MainActor private func make() -> (CategoryWorkspaceAPI,TaskCategoryWorkspace,TaskStore) {
        let api = CategoryWorkspaceAPI(), store = TaskStore(service:TaskService(client:CategoryWorkspaceAPI()))
        return (api,TaskCategoryWorkspace(service:TaskCategoryService(client:api),store:store),store)
    }
    @MainActor private func reached(_ condition: () -> Bool) async throws {
        for _ in 0..<10000 { if condition() { return }; await Task.yield() }; XCTFail("Missing suspension"); throw CancellationError()
    }
    @MainActor func testDirtySwitchCancelAndStaleEditorCannotOverwriteName() async throws {
        let (_,model,_) = make(); let owner = try XCTUnwrap(model.open(tasks:[]))
        await model.load(contextID:owner); XCTAssertEqual(model.selection,.category(8))
        let editor = model.editorID; model.setName("edited e\u{301} 中文 한국어",contextID:owner,editorID:editor)
        model.select(.category(9),contextID:owner,editorID:editor)
        let cancelled = try XCTUnwrap(model.decision).id
        _ = await model.resolve(id:cancelled,accept:false,contextID:owner)
        XCTAssertEqual(model.name,"edited e\u{301} 中文 한국어")
        model.select(.category(9),contextID:owner,editorID:editor)
        _ = await model.resolve(id:try XCTUnwrap(model.decision).id,accept:true,contextID:owner)
        model.setName("late",contextID:owner,editorID:editor); XCTAssertEqual(model.name,"category 9")
    }
    @MainActor func testConfirmedDeleteInvalidatesOldReadsAndRetainsTasks() async throws {
        let (api,model,store) = make(); let owner = try XCTUnwrap(model.open(tasks:[])); await model.load(contextID:owner)
        api.holdReads = true; let read = Task { await model.load(contextID:owner) }; try await reached { api.reads.count == 2 }
        model.requestDelete(contextID:owner,editorID:model.editorID)
        let confirmed = await model.resolve(id:try XCTUnwrap(model.decision).id,accept:true,contextID:owner)
        XCTAssertTrue(confirmed); XCTAssertFalse(model.categories.contains { $0.id == 8 }); XCTAssertFalse(store.isMutating)
        api.reads["/api/task-categories"]?.resume(returning:try api.response(["categories":[api.row(8)]]))
        api.reads["/api/tasks"]?.resume(returning:try api.response(["error":"late"],status:503))
        await read.value; XCTAssertFalse(model.categories.contains { $0.id == 8 }); XCTAssertNil(model.taskFailure)
    }
    @MainActor func testUnknownPersistsAcrossCloseAndBlocksRetryUntilExplicitDiscard() async throws {
        let (api,model,_) = make(); var owner = try XCTUnwrap(model.open(tasks:[])); await model.load(contextID:owner)
        model.setName("keep",contextID:owner,editorID:model.editorID); api.status = 503
        let failed = await model.save(contextID:owner,editorID:model.editorID); XCTAssertFalse(failed); XCTAssertTrue(model.uncertain)
        model.close(contextID:owner); owner = try XCTUnwrap(model.open(tasks:[]))
        let retry = await model.save(contextID:owner,editorID:model.editorID); XCTAssertFalse(retry); XCTAssertEqual(model.name,"keep")
        XCTAssertEqual(api.calls.filter { $0.0 == "PATCH" }.count,1)
        model.requestDiscard(contextID:owner)
        _ = await model.resolve(id:try XCTUnwrap(model.decision).id,accept:true,contextID:owner)
        XCTAssertFalse(model.uncertain); XCTAssertEqual(model.selection,.new)
        model.setName("conflict",contextID:owner,editorID:model.editorID); api.status = 409
        let conflict = await model.save(contextID:owner,editorID:model.editorID); XCTAssertFalse(conflict); XCTAssertFalse(model.uncertain)
    }
    @MainActor func testQueuedDeleteResetHasZeroDispatchAndGateSurvivesInFlightReset() async throws {
        let (api,model,store) = make(); var owner = try XCTUnwrap(model.open(tasks:[])); await model.load(contextID:owner)
        model.requestDelete(contextID:owner,editorID:model.editorID)
        model.resolveFromUI(id:try XCTUnwrap(model.decision).id,accept:true,contextID:owner)
        model.reset(); store.reset(); XCTAssertTrue(model.isMutating); XCTAssertTrue(store.isMutating)
        try await reached { !model.isMutating }; XCTAssertFalse(api.calls.contains { $0.0 == "DELETE" }); XCTAssertFalse(store.isMutating)
        owner = try XCTUnwrap(model.open(tasks:[])); await model.load(contextID:owner); api.hold = true
        let editor = model.editorID; let pending = Task { await model.save(contextID:owner,editorID:editor) }
        try await reached { api.pending.count == 1 }; model.reset(); store.reset()
        XCTAssertNil(model.open(tasks:[])); api.pending[0].resume(returning:try api.response(api.row()))
        let late = await pending.value; XCTAssertFalse(late); XCTAssertTrue(model.categories.isEmpty); XCTAssertFalse(store.isMutating)
    }
    @MainActor func testInlineCreateCapturesParentAndDoesNotReopenAfterSuspend() async throws {
        let (api,model,_) = make(); let parent = UUID(), owner = try XCTUnwrap(model.open(tasks:[],inlineOwner:parent,seedName:"new category"))
        var savedOwner: UUID?; var changes = 0; model.onChange = { _,inline in savedOwner = inline; changes += 1 }
        api.hold = true; let editor = model.editorID
        let pending = Task { await model.save(contextID:owner,editorID:editor) }; try await reached { api.pending.count == 1 }
        model.suspend(); api.pending[0].resume(returning:try api.response(api.row(10),status:201))
        let confirmed = await pending.value; XCTAssertTrue(confirmed); XCTAssertEqual(savedOwner,parent); XCTAssertEqual(changes,1); XCTAssertNil(model.context)
    }
}
