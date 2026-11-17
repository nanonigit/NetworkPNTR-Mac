import XCTest
import Observation
import AppKit
import SwiftUI
@testable import NetworkPNTRCore
@testable import NetworkPNTRMac

@MainActor private final class BulkAPI: BackendJSONTransport {
    var tasks: [[String:Any]] = []
    var failReads = false
    var hold = false
    var statuses: [String:Int] = [:]
    var calls: [(String,String,Data?)] = []
    var held: [CheckedContinuation<BackendHTTPResponse,Error>] = []
    var batch: [String:Any]?
    func response(_ value: Any, status: Int = 200) throws -> BackendHTTPResponse { .init(status:status,body:try JSONSerialization.data(withJSONObject:value)) }
    func deletion(_ id: String, count: Int64 = 1, warning: Bool = false) throws -> BackendHTTPResponse {
        try response(["deleted":id,"assets_deleted":count,"assets_detached":count,"traffic_deleted":count,"files_deleted":true,"findings_deleted":count,"llm_records_deleted":count,"cleanup_warning":warning ? "private warning /state/file" : ""])
    }
    func send(method: String,path: String,body: Data?,bearer: String?) async throws -> BackendHTTPResponse {
        calls.append((method,path,body))
        if method == "GET" {
            if failReads { return try response(["error":"private refresh"],status:503) }
            if path == "/api/tasks" { return try response(["tasks":tasks,"active":"7"]) }
            if path == "/api/task-categories" { return try response(["categories":[]]) }
            return try response(tasks[0])
        }
        if hold { return try await withCheckedThrowingContinuation { held.append($0) } }
        let id = String(path.split(separator:"/").last!)
        if let status = statuses[id] { return try response(["error":"private token"],status:status) }
        if let batch { return try response(batch) }
        return try deletion(id)
    }
}

final class TaskBulkWorkspaceTests: XCTestCase {
    @MainActor func testLiveStopAtWorkspaceBusyPreventsDeleteHandoff() async throws {
        let (api,model,store)=try await make();select(["7","8"],model);XCTAssertTrue(model.begin(.delete))
        let owner=try XCTUnwrap(model.context).id
        withObservationTracking {_ = model.isMutating} onChange:{MainActor.assumeIsolated{store.stop()}}
        _ = await model.submit(contextID:owner)
        XCTAssertFalse(api.calls.contains{$0.0 == "DELETE"});XCTAssertEqual(model.items.map(\.state),[.notStarted,.notStarted])
        XCTAssertTrue(model.uncertainIDs.isEmpty);XCTAssertFalse(store.isMutating)
    }
    @MainActor func testRevocationAfterFirstKnownDeleteDoesNotSendNextOrMarkItUnknown() async throws {
        let (api,model,store)=try await make();select(["7","8"],model);XCTAssertTrue(model.begin(.delete))
        let owner=try XCTUnwrap(model.context).id
        withObservationTracking {_ = model.items.count} onChange:{MainActor.assumeIsolated{store.stop()}}
        _ = await model.submit(contextID:owner)
        XCTAssertEqual(api.calls.filter{$0.0 == "DELETE"}.map(\.1),["/api/tasks/7"])
        XCTAssertEqual(model.items.map(\.state),[.succeeded,.notStarted]);XCTAssertTrue(model.uncertainIDs.isEmpty)
        XCTAssertFalse(store.isMutating)
    }
    @MainActor private func make(_ count: Int = 3) async throws -> (BulkAPI,TaskBulkWorkspace,TaskStore) {
        let api = BulkAPI()
        let url = URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("NetworkPNTRCoreTests/Fixtures/task-contract.json")
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with:Data(contentsOf:url)) as? [String:Any]), raw = try XCTUnwrap(root["task"] as? [String:Any])
        api.tasks = (0..<count).map { index in var row = raw; row["id"] = String(index+7); row["status"] = index == 0 ? "running" : index == 1 ? "paused" : "done"; return row }
        let store = TaskStore(service:TaskService(client:api)); await store.refreshList(); api.failReads = true
        return (api,TaskBulkWorkspace(store:store,service:TaskService(client:api),categoryService:TaskCategoryService(client:api)),store)
    }
    @MainActor private func reached(_ condition: () -> Bool) async throws {
        for _ in 0..<10000 { if condition() { return }; await Task.yield() }; XCTFail("Missing suspension"); throw CancellationError()
    }
    @MainActor private func select(_ ids: [String], _ model: TaskBulkWorkspace) {
        for id in ids { model.setSelected(id,selected:true,owner:model.viewOwner) }
    }
    @MainActor func testSelectionIsLiveCrossFilterAndDoesNotNavigateDetail() async throws {
        let (api,model,store) = try await make(); select(["7","8","foreign"],model)
        XCTAssertEqual(model.selectedIDs,Set(["7","8"])); XCTAssertNil(store.selectedID)
        model.setAll(ids:["8","9"],selected:true,owner:model.viewOwner); XCTAssertEqual(model.selectedIDs,Set(["7","8","9"]))
        model.setAll(ids:["8","9"],selected:false,owner:model.viewOwner); XCTAssertEqual(model.selectedIDs,Set(["7"]))
        model.reconcileSelection(); XCTAssertEqual(model.selectedIDs,Set(["7"]))
        api.failReads = false; api.tasks.removeFirst(); await store.refreshList(); model.reconcileSelection(); XCTAssertTrue(model.selectedIDs.isEmpty)
    }
    @MainActor func testSerialDeleteSnapshotsFlagsAndAggregatesWithoutIntegerOverflow() async throws {
        let (api,model,store) = try await make(); select(["7","8","9"],model)
        XCTAssertTrue(model.begin(.delete)); let owner = try XCTUnwrap(model.context).id
        XCTAssertFalse(model.options.deleteFiles); model.setOption(\.deleteFiles,value:true,contextID:owner)
        api.hold = true; let operation = Task { await model.submit(contextID:owner) }
        try await reached { api.held.count == 1 }; XCTAssertTrue(store.isMutating)
        model.setOption(\.deleteAssets,value:true,contextID:owner)
        api.held[0].resume(returning:try api.deletion("7",count:Int64.max,warning:true))
        try await reached { api.held.count == 2 }; XCTAssertEqual(model.completedCount,1); XCTAssertFalse(model.selectedIDs.contains("7"))
        api.held[1].resume(returning:try api.response(["error":"private failure"],status:404))
        try await reached { api.held.count == 3 }
        api.held[2].resume(returning:try api.deletion("9",count:Int64.max))
        let finished = await operation.value; XCTAssertTrue(finished); XCTAssertEqual(model.completedCount,3)
        XCTAssertEqual(model.items.map(\.state),[.succeeded,.rejected,.succeeded]); XCTAssertEqual(model.selectedIDs,Set(["8"]))
        XCTAssertEqual(model.totals.assetsText,"18446744073709551614"); XCTAssertEqual(model.warningIDs,["7"])
        XCTAssertEqual(store.list.value?.map(\.id),["8"]); XCTAssertFalse(store.isMutating)
        let writes = api.calls.filter{$0.0 == "DELETE"}; XCTAssertEqual(writes.map(\.1),["/api/tasks/7","/api/tasks/8","/api/tasks/9"])
        for call in writes {
            let body = try XCTUnwrap(JSONSerialization.jsonObject(with:XCTUnwrap(call.2)) as? [String:Any])
            XCTAssertEqual(body.count,5); XCTAssertEqual(body["delete_files"] as? Bool,true); XCTAssertEqual(body["delete_assets"] as? Bool,false)
        }
        XCTAssertFalse(String(describing:model.items).contains("private"))
    }
    @MainActor func testUnknownBlocksSameIDUntilCapturedExplicitAcknowledgement() async throws {
        let (api,model,_) = try await make(); select(["7","8"],model); api.statuses["7"] = 503
        XCTAssertTrue(model.begin(.delete)); let owner = try XCTUnwrap(model.context).id
        let finished = await model.submit(contextID:owner); XCTAssertTrue(finished)
        XCTAssertEqual(model.uncertainIDs,Set(["7"])); XCTAssertEqual(model.items.map(\.state),[.unconfirmed,.succeeded])
        model.close(contextID:owner); XCTAssertFalse(model.begin(.delete))
        model.requestAcknowledgement(); let ack = try XCTUnwrap(model.acknowledgement).id
        model.resolveAcknowledgement(id:UUID(),accept:true); XCTAssertEqual(model.uncertainIDs,Set(["7"]))
        model.resolveAcknowledgement(id:ack,accept:false); model.requestAcknowledgement()
        let next = try XCTUnwrap(model.acknowledgement).id
        model.resolveAcknowledgement(id:ack,accept:true); XCTAssertEqual(model.uncertainIDs,Set(["7"]))
        model.resolveAcknowledgement(id:next,accept:true); XCTAssertTrue(model.uncertainIDs.isEmpty); XCTAssertTrue(model.begin(.delete))
        XCTAssertEqual(api.calls.filter{$0.0 == "DELETE"}.count,2)
    }
    @MainActor func testPauseEligibilityPartialResumeAndSelectionPolicy() async throws {
        let (api,model,store) = try await make(); select(["7","8","9"],model)
        XCTAssertTrue(model.begin(.control(.pause))); let owner = try XCTUnwrap(model.context).id
        XCTAssertEqual(model.context?.ids,["7"])
        api.batch = ["items":[["id":"7","ok":true,"status":"paused","queued":false]]]
        _ = await model.submit(contextID:owner); XCTAssertEqual(store.list.value?.first?.status,"paused")
        XCTAssertEqual(model.selectedIDs,Set(["7","8","9"])); model.close(contextID:owner)
        XCTAssertTrue(model.begin(.control(.resume))); let resume = try XCTUnwrap(model.context).id
        XCTAssertEqual(model.context?.ids,["7","8"])
        api.batch = ["items":[["id":"7","ok":true,"status":"queued","queued":true],["id":"8","ok":false,"error":"private"]]]
        _ = await model.submit(contextID:resume); XCTAssertEqual(model.queuedIDs,["7"]); XCTAssertEqual(model.items.map(\.state),[.succeeded,.rejected])
        XCTAssertEqual(model.selectedIDs,Set(["7","8","9"]))
    }
    @MainActor func testCategoryMoveExplicitNullClearsAllSelectionOnAnySuccess() async throws {
        let (api,model,_) = try await make(); select(["7","8"],model)
        XCTAssertTrue(model.begin(.move)); let owner = try XCTUnwrap(model.context).id
        api.batch = ["items":[["id":"7","ok":true],["id":"8","ok":false]],"category":NSNull()]
        _ = await model.submit(contextID:owner)
        XCTAssertTrue(model.selectedIDs.isEmpty); XCTAssertEqual(model.items.map(\.state),[.succeeded,.rejected])
        let call = try XCTUnwrap(api.calls.first{$0.1 == "/api/tasks/category/batch"})
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with:XCTUnwrap(call.2)) as? [String:Any]); XCTAssertTrue(body["category_id"] is NSNull)
    }
    @MainActor func testSuspendCancelsInFlightAndMarksRemainingNotStarted() async throws {
        let (api,model,store) = try await make(); select(["7","8"],model); XCTAssertTrue(model.begin(.delete))
        let owner = try XCTUnwrap(model.context).id; api.hold = true
        let operation = Task { await model.submit(contextID:owner) }; try await reached { api.held.count == 1 }
        let oldOwner = model.viewOwner; model.suspend(); XCTAssertTrue(store.isMutating)
        api.held[0].resume(returning:try api.deletion("7")); _ = await operation.value
        XCTAssertEqual(model.items.map(\.state),[.unconfirmed,.notStarted]); XCTAssertEqual(model.uncertainIDs,Set(["7"]))
        model.setSelected("9",selected:true,owner:oldOwner); XCTAssertFalse(model.selectedIDs.contains("9")); XCTAssertFalse(store.isMutating)
        XCTAssertEqual(api.calls.filter{$0.0 == "DELETE"}.count,1)
    }
    @MainActor func testResetBeforeAndAfterDispatchCannotMutateNewSession() async throws {
        let (api,model,store) = try await make(); select(["7","8"],model); XCTAssertTrue(model.begin(.delete))
        model.submitFromUI(contextID:try XCTUnwrap(model.context).id); model.reset(); store.reset()
        XCTAssertTrue(model.isMutating); try await reached { !model.isMutating }
        XCTAssertFalse(api.calls.contains{$0.0 == "DELETE"}); XCTAssertFalse(store.isMutating)
        api.failReads = false; await store.refreshList(); api.failReads = true
        select(["7","8"],model); XCTAssertTrue(model.begin(.delete)); let owner = try XCTUnwrap(model.context).id; api.hold = true
        let operation = Task { await model.submit(contextID:owner) }; try await reached { api.held.count == 1 }
        model.reset(); store.reset(); XCTAssertTrue(store.isMutating)
        api.held[0].resume(returning:try api.deletion("7")); _ = await operation.value
        XCTAssertTrue(model.items.isEmpty); XCTAssertTrue(model.selectedIDs.isEmpty); XCTAssertNil(store.list.value); XCTAssertFalse(store.isMutating)
    }
    @MainActor func testControlMoveLimitDoesNotLimitSerialDeleteOrPermitCancelledStart() async throws {
        let (api,model,_) = try await make(101); select((7...107).map(String.init),model)
        XCTAssertFalse(model.begin(.move)); XCTAssertTrue(model.begin(.delete)); let owner = try XCTUnwrap(model.context).id
        XCTAssertEqual(model.context?.ids.count,101)
        let task = Task { await model.submit(contextID:owner) }; task.cancel()
        let result = await task.value; XCTAssertFalse(result); XCTAssertFalse(model.isMutating)
        XCTAssertFalse(api.calls.contains{$0.0 == "DELETE"})
    }
    @MainActor func testAuthenticationFailureStopsRemainingDeletionRequests() async throws {
        for status in [401,403] {
            let (api,model,_) = try await make(); select(["7","8"],model); api.statuses["7"] = status
            XCTAssertTrue(model.begin(.delete)); _ = await model.submit(contextID:try XCTUnwrap(model.context).id)
            XCTAssertEqual(model.items.map(\.state),[.rejected,.notStarted]); XCTAssertEqual(model.selectedIDs,Set(["7","8"]))
            XCTAssertEqual(api.calls.filter{$0.0 == "DELETE"}.count,1); XCTAssertTrue(model.uncertainIDs.isEmpty)
        }
    }
    @MainActor func testQueuedSameSessionCancellationReportsEveryIDNotStarted() async throws {
        let (api,model,store) = try await make(); select(["7","8"],model); XCTAssertTrue(model.begin(.delete))
        model.submitFromUI(contextID:try XCTUnwrap(model.context).id); model.suspend()
        try await reached { !model.isMutating }
        XCTAssertEqual(model.items.map(\.state),[.notStarted,.notStarted]); XCTAssertEqual(model.completedCount,0)
        XCTAssertTrue(model.uncertainIDs.isEmpty); XCTAssertFalse(api.calls.contains{$0.0 == "DELETE"}); XCTAssertFalse(store.isMutating)
    }

    @MainActor func testScreenGatesAndStaleBindingsPreserveCapturedBulkDialog() async throws {
        let (api,_,store) = try await make()
        let screen = TaskScreenModel(store:store,creationService:TaskCreationService(client:api),categoryService:TaskCategoryService(client:api),bulkService:TaskService(client:api))
        let model = try XCTUnwrap(screen.bulk), epoch = model.viewOwner
        let checkbox = TaskBulkBindings.selected(screen:screen,id:"7",owner:epoch); checkbox.wrappedValue = true
        XCTAssertTrue(screen.beginBulk(.delete)); let first = try XCTUnwrap(model.context).id
        let old = TaskBulkBindings.presentation(model:model,contextID:first)
        let option = TaskBulkBindings.cleanup(model:model,contextID:first,key:\.deleteFiles)
        XCTAssertFalse(screen.beginCreate()); XCTAssertFalse(screen.beginCategories()); XCTAssertTrue(screen.busy)
        checkbox.wrappedValue = false; XCTAssertEqual(model.selectedIDs,Set(["7"]))
        model.close(contextID:first); XCTAssertTrue(screen.beginBulk(.delete)); let next = try XCTUnwrap(model.context).id
        old.wrappedValue = nil; option.wrappedValue = true
        XCTAssertEqual(model.context?.id,next); XCTAssertFalse(model.options.deleteFiles)
        screen.stop(); checkbox.wrappedValue = false; XCTAssertEqual(model.selectedIDs,Set(["7"]))
        screen.reset(); XCTAssertTrue(model.selectedIDs.isEmpty); XCTAssertTrue(model.uncertainIDs.isEmpty)
    }
    @MainActor func testOffscreenEnglishJapaneseBulkViewsKeepSelectionWithoutRequests() async throws {
        let (api,model,_) = try await make(); select(["7","8"],model); let before = api.calls.count
        for kind: TaskBulkKind in [.delete,.move,.control(.pause),.control(.resume)] {
            XCTAssertTrue(model.begin(kind)); let owner = try XCTUnwrap(model.context).id
            for language in AppLanguage.allCases {
                let host = NSHostingView(rootView:TaskBulkView(model:model,contextID:owner).environment(\.locale,language.locale))
                host.frame = NSRect(x:0,y:0,width:600,height:650); host.layoutSubtreeIfNeeded()
                XCTAssertNil(host.window); XCTAssertTrue(host.fittingSize.width.isFinite)
                XCTAssertEqual(model.selectedIDs,Set(["7","8"])); XCTAssertEqual(model.context?.id,owner)
            }
            model.close(contextID:owner)
        }
        XCTAssertEqual(api.calls.count,before)
    }

    @MainActor func testBatchMismatchBlocksRetryWhileKnownMoveRejectionStaysExplicit() async throws {
        let (api,model,_) = try await make(); select(["7","8"],model)
        XCTAssertTrue(model.begin(.control(.pause))); let first = try XCTUnwrap(model.context).id
        api.batch = ["items":[["id":"9","ok":true,"status":"paused","queued":false]]]
        _ = await model.submit(contextID:first)
        XCTAssertEqual(model.items.map(\.state),[.unconfirmed]); XCTAssertEqual(model.uncertainIDs,Set(["7"]))
        model.close(contextID:first); model.setSelected("7",selected:false,owner:model.viewOwner)
        XCTAssertTrue(model.begin(.move)); let second = try XCTUnwrap(model.context).id
        api.statuses["batch"] = 400
        _ = await model.submit(contextID:second)
        XCTAssertEqual(model.items.map(\.state),[.rejected]); XCTAssertEqual(model.selectedIDs,Set(["8"]))
        XCTAssertEqual(model.uncertainIDs,Set(["7"])); XCTAssertEqual(api.calls.filter{$0.0 == "POST"}.count,2)
    }

}
