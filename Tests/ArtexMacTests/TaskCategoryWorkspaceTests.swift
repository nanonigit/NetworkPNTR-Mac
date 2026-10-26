import XCTest
import AppKit
import SwiftUI
@testable import ArtexCore
@testable import ArtexMac

@MainActor private final class CategoryWorkspaceAPI: BackendJSONTransport {
    var calls: [(String,String,Data?)] = []
    var hold = false
    var holdReads = false
    var status = 200
    var readStatus = 200
    var taskRows: [[String:Any]] = []
    var categoryRows: [[String:Any]]?
    var pending: [CheckedContinuation<BackendHTTPResponse,Error>] = []
    var reads: [String:CheckedContinuation<BackendHTTPResponse,Error>] = [:]
    func row(_ id: Int64 = 8) -> [String:Any] { ["id":id,"name":"category \(id)","task_count":0,"created_at":"c","updated_at":"u"] }
    func response(_ value: Any, status: Int = 200) throws -> BackendHTTPResponse { .init(status:status,body:try JSONSerialization.data(withJSONObject:value)) }
    func send(method: String,path: String,body: Data?,bearer: String?) async throws -> BackendHTTPResponse {
        calls.append((method,path,body))
        if method == "GET" {
            if readStatus != 200 { return try response(["error":"private read"],status:readStatus) }
            if holdReads { return try await withCheckedThrowingContinuation { reads[path] = $0 } }
            if path == "/api/task-categories" { return try response(["categories":categoryRows ?? [row(8),row(9)]]) }
            return try response(["tasks":taskRows,"active":""])
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
    @MainActor func testInlineIntegrationProtectsParentDraftAndSelectsOnlyMatchingOwner() async throws {
        let api = CategoryWorkspaceAPI(), store = TaskStore(service:TaskService(client:CategoryWorkspaceAPI()))
        let screen = TaskScreenModel(store:store,creationService:TaskCreationService(client:api),templateService:TaskTemplateService(client:api),categoryService:TaskCategoryService(client:api))
        XCTAssertTrue(screen.beginCreate()); let creation = try XCTUnwrap(screen.creation), owner = try XCTUnwrap(creation.context).id
        creation.update(\.draft.description,value:"e\u{301} 中文 한국어",contextID:owner); creation.update(\.draft.goal,value:"goal",contextID:owner)
        let draft = creation.draftID, text = Data(creation.form.draft.description.utf8)
        XCTAssertTrue(creation.openCategoryCreator(contextID:owner))
        let workspace = try XCTUnwrap(screen.categories), categoryOwner = try XCTUnwrap(workspace.context).id
        XCTAssertTrue(screen.busy); creation.setPickerPresented(true,contextID:owner); XCTAssertFalse(creation.isPicking)
        creation.discard(contextID:owner); creation.close(contextID:owner)
        XCTAssertEqual(creation.context?.id,owner); XCTAssertEqual(creation.draftID,draft)
        XCTAssertFalse(creation.openTemplateManager(asSeed:false,contextID:owner))
        let forbidden = await creation.submit(contextID:owner); XCTAssertFalse(forbidden)
        workspace.setName("new",contextID:categoryOwner,editorID:workspace.editorID)
        let saved = await workspace.save(contextID:categoryOwner,editorID:workspace.editorID); XCTAssertTrue(saved)
        XCTAssertEqual(creation.form.draft.categoryId,10); XCTAssertEqual(creation.categories.value?.first?.id,10)
        XCTAssertEqual(Data(creation.form.draft.description.utf8),text); XCTAssertEqual(creation.draftID,draft)
        XCTAssertTrue(creation.openCategoryCreator(contextID:owner))
        let stale = try XCTUnwrap(workspace.context).id; workspace.setName("late",contextID:stale,editorID:workspace.editorID)
        api.hold = true; let editor = workspace.editorID
        let pending = Task { await workspace.save(contextID:stale,editorID:editor) }; try await reached { api.pending.count == 1 }
        screen.stop(); XCTAssertNil(creation.context)
        api.pending[0].resume(returning:try api.response(api.row(11),status:201))
        _ = await pending.value; XCTAssertNil(creation.context); XCTAssertEqual(Data(creation.form.draft.description.utf8),text)
        XCTAssertEqual(creation.form.draft.categoryId,10)
    }
    @MainActor func testBindingsAndOffscreenUIUseCapturedOwnerAcrossLanguageSwitch() async throws {
        let (_,model,_) = make(); let owner = try XCTUnwrap(model.open(tasks:[])); await model.load(contextID:owner)
        let editor = model.editorID
        let binding = TaskCategoryBindings.name(model:model,contextID:owner,editorID:editor)
        let old = TaskCategoryBindings.presentation(model:model,contextID:owner)
        model.close(contextID:owner); let next = try XCTUnwrap(model.open(tasks:[]))
        old.wrappedValue = nil; binding.wrappedValue = "late"
        XCTAssertEqual(model.context?.id,next); XCTAssertEqual(model.name,"category 8")
        for language in AppLanguage.allCases {
            let host = NSHostingView(rootView:TaskCategoryView(model:model,contextID:next).environment(\.locale,language.locale))
            host.frame = NSRect(x:0,y:0,width:820,height:650); host.layoutSubtreeIfNeeded()
            XCTAssertNil(host.window); XCTAssertTrue(host.fittingSize.width.isFinite); XCTAssertEqual(model.editorID,editor)
        }
    }

    private func taskRow(_ id: String, category: Int64 = 8) throws -> [String:Any] {
        let url = URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("ArtexCoreTests/Fixtures/task-contract.json")
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with:Data(contentsOf:url)) as? [String:Any]); var row = try XCTUnwrap(root["task"] as? [String:Any])
        row["id"] = id; row["category_id"] = category; row["category_name"] = "category \(category)"; return row
    }
    @MainActor func testPartialMoveKeepsFailedSelectionsAndRuntimeData() async throws {
        let (api,model,store) = make(); api.taskRows = [try taskRow("7"),try taskRow("9")]
        let owner = try XCTUnwrap(model.open(tasks:[])); await model.load(contextID:owner)
        let editor = model.editorID, original = try XCTUnwrap(model.tasks.first)
        for id in ["7","9"] { model.selectTask(id,selected:true,contextID:owner,editorID:editor) }
        model.requestMove(ids:["7","9"],target:9,contextID:owner,editorID:editor)
        let cancel = try XCTUnwrap(model.decision).id; _ = await model.resolve(id:cancel,accept:false,contextID:owner)
        XCTAssertEqual(model.selectedTaskIDs,Set(["7","9"])); XCTAssertFalse(api.calls.contains{$0.0 == "POST"})
        model.requestMove(ids:["7","9"],target:9,contextID:owner,editorID:editor)
        api.hold = true
        let operation = Task { await model.resolve(id:try XCTUnwrap(model.decision).id,accept:true,contextID:owner) }
        try await reached { api.pending.count == 1 }; XCTAssertTrue(store.isMutating)
        let forbidden = await store.update(id:"7",patch:.init(name:"blocked"))
        if case .notStarted = forbidden {} else { XCTFail("Concurrent store mutation allowed") }
        api.pending[0].resume(returning:try api.response(["items":[["id":"7","ok":true],["id":"9","ok":false,"error":"secret"]],"category":api.row(9)]))
        let confirmed = try await operation.value; XCTAssertTrue(confirmed); XCTAssertEqual(model.selectedTaskIDs,Set(["9"]))
        XCTAssertEqual(model.tasks.first?.categoryId,9); XCTAssertEqual(model.tasks.last?.categoryId,8)
        XCTAssertEqual(model.tasks.first?.description,original.description); XCTAssertEqual(model.tasks.first?.status,original.status)
        XCTAssertEqual(model.tasks.first?.tokens,original.tokens); XCTAssertTrue(model.countsStale); XCTAssertFalse(store.isMutating)
        XCTAssertEqual(api.calls.filter{$0.0 == "POST"}.count,1)
    }
    @MainActor func testSingleMoveAndConfirmedReceiptSurviveReadFailure() async throws {
        let (api,model,_) = make(); api.taskRows = [try taskRow("7")]
        let owner = try XCTUnwrap(model.open(tasks:[])); await model.load(contextID:owner)
        model.requestMove(ids:["not-owned"],target:9,contextID:owner,editorID:model.editorID); XCTAssertNil(model.decision)
        model.requestMove(ids:["7"],target:44,contextID:owner,editorID:model.editorID); XCTAssertNil(model.decision)
        model.requestMove(ids:["7"],target:9,contextID:owner,editorID:model.editorID)
        api.hold = true; let decision = try XCTUnwrap(model.decision).id
        let operation = Task { await model.resolve(id:decision,accept:true,contextID:owner) }; try await reached { api.pending.count == 1 }
        api.pending[0].resume(returning:try api.response(taskRow("7",category:9)))
        let moved = await operation.value; XCTAssertTrue(moved); XCTAssertEqual(model.tasks.first?.categoryId,9)
        XCTAssertEqual(api.calls.last?.1,"/api/tasks/7/category")
        api.readStatus = 503; await model.load(contextID:owner)
        XCTAssertNotNil(model.lastChange); XCTAssertNotNil(model.categoryFailure); XCTAssertNotNil(model.taskFailure)
        XCTAssertEqual(model.tasks.first?.categoryId,9); XCTAssertFalse(model.uncertain)
    }

    @MainActor func testOpeningManagerInvalidatesHeldBackgroundCatalogLoad() async throws {
        let (api,model,_) = make(); api.holdReads = true
        let background = Task { await model.refreshCatalog() }; try await reached { api.reads["/api/task-categories"] != nil }
        let old = try XCTUnwrap(api.reads["/api/task-categories"])
        let owner = try XCTUnwrap(model.open(tasks:[])); XCTAssertFalse(model.isLoading)
        api.holdReads = false; await model.load(contextID:owner)
        XCTAssertEqual(model.categories.map(\.id),[8,9]); XCTAssertEqual(model.selection,.category(8))
        old.resume(returning:try api.response(["categories":[api.row(44)]])); await background.value
        XCTAssertEqual(model.categories.map(\.id),[8,9]); XCTAssertEqual(model.context?.id,owner)
    }
    @MainActor func testWrongSheetScopeCannotDismissAnotherOwner() throws {
        let (_,model,_) = make(); let owner = try XCTUnwrap(model.open(tasks:[]))
        let wrong = TaskCategoryBindings.presentation(model:model,contextID:owner,inlineOwner:UUID())
        XCTAssertNil(wrong.wrappedValue); wrong.wrappedValue = nil
        XCTAssertEqual(model.context?.id,owner)
        model.close(contextID:owner)
        let parent = UUID(), next = try XCTUnwrap(model.open(tasks:[],inlineOwner:parent))
        let manager = TaskCategoryBindings.presentation(model:model,contextID:next)
        XCTAssertNil(manager.wrappedValue); manager.wrappedValue = nil
        XCTAssertEqual(model.context?.id,next)
    }

    @MainActor func testInlineExactExistingNameSelectsWithoutDuplicateCreate() async throws {
        let (api,model,_) = make(); let parent = UUID(), owner = try XCTUnwrap(model.open(tasks:[],inlineOwner:parent))
        await model.load(contextID:owner)
        var selected: Int64?; model.onChange = { change,context in
            XCTAssertEqual(context,parent); if case .saved(let row) = change { selected = row.id }
        }
        model.setName("  CATEGORY 8  ",contextID:owner,editorID:model.editorID)
        let saved = await model.save(contextID:owner,editorID:model.editorID)
        XCTAssertTrue(saved); XCTAssertEqual(selected,8); XCTAssertNil(model.context)
        XCTAssertFalse(api.calls.contains { $0.0 == "POST" })
    }
    @MainActor func testCatalogReceiptDoesNotCancelOtherCreationOptionReads() async throws {
        let api = CategoryWorkspaceAPI(), store = TaskStore(service:TaskService(client:CategoryWorkspaceAPI()))
        let screen = TaskScreenModel(store:store,creationService:TaskCreationService(client:api),categoryService:TaskCategoryService(client:api))
        let workspace = try XCTUnwrap(screen.categories); api.holdReads = true
        let background = Task { await workspace.refreshCatalog() }; try await reached { api.reads["/api/task-categories"] != nil }
        let old = try XCTUnwrap(api.reads["/api/task-categories"])
        XCTAssertTrue(screen.beginCreate()); let creation = try XCTUnwrap(screen.creation), owner = try XCTUnwrap(creation.context).id
        let loading = Task { await creation.load(contextID:owner) }; try await reached { api.reads.count == 5 }
        old.resume(returning:try api.response(["categories":[api.row(9)]])); await background.value
        api.reads["/api/task-categories"]?.resume(returning:try api.response(["categories":[api.row(8)]]))
        api.reads["/api/companies"]?.resume(returning:try api.response([["id":1,"name":"company"]]))
        api.reads["/api/llm/profiles"]?.resume(returning:try api.response(["profiles":[]]))
        api.reads["/api/task-templates"]?.resume(returning:try api.response(["templates":[]]))
        api.reads["/api/tasks"]?.resume(returning:try api.response(["tasks":[],"active":""]))
        await loading.value
        XCTAssertEqual(creation.categories.value?.map(\.id),[9]); XCTAssertEqual(creation.companies.value?.map(\.id),[1])
        XCTAssertNotNil(creation.profiles.value); XCTAssertNotNil(creation.sources.value); XCTAssertFalse(creation.isLoading)
    }

    @MainActor func testInitialSelectionUsesBothCatalogAndTaskResponses() async throws {
        let (emptyAPI,empty,_) = make(); emptyAPI.categoryRows = []
        let first = try XCTUnwrap(empty.open(tasks:[])); await empty.load(contextID:first)
        XCTAssertEqual(empty.selection,.new)
        let (api,model,_) = make(); api.categoryRows = []; api.holdReads = true
        let owner = try XCTUnwrap(model.open(tasks:[]))
        let loading = Task { await model.load(contextID:owner) }; try await reached { api.reads.count == 2 }
        api.reads["/api/task-categories"]?.resume(returning:try api.response(["categories":[]]))
        for _ in 0..<50 { await Task.yield() }
        XCTAssertEqual(model.selection,.new)
        var uncategorized = try taskRow("7"); uncategorized["category_id"] = NSNull(); uncategorized["category_name"] = NSNull()
        api.reads["/api/tasks"]?.resume(returning:try api.response(["tasks":[uncategorized],"active":""]))
        await loading.value; XCTAssertEqual(model.selection,.uncategorized)
        let (otherAPI,other,_) = make(); otherAPI.holdReads = true
        let otherOwner = try XCTUnwrap(other.open(tasks:[]))
        let otherLoad = Task { await other.load(contextID:otherOwner) }; try await reached { otherAPI.reads.count == 2 }
        other.select(.uncategorized,contextID:otherOwner,editorID:other.editorID)
        otherAPI.reads["/api/task-categories"]?.resume(returning:try otherAPI.response(["categories":[otherAPI.row(8)]]))
        otherAPI.reads["/api/tasks"]?.resume(returning:try otherAPI.response(["tasks":[],"active":""]))
        await otherLoad.value; XCTAssertEqual(other.selection,.uncategorized)

    }

}
