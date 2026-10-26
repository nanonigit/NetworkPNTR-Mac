import XCTest
import ArtexCore
@testable import ArtexMac

@MainActor private final class ArchiveActionAPI: BackendJSONTransport {
    var tasks: [[String:Any]] = []
    var rows: [String] = []
    var writes: [(String,String,Data?)] = []
    var replies: [BackendHTTPResponse] = []
    var hold = false
    var held: [CheckedContinuation<BackendHTTPResponse,Error>] = []
    func send(method: String,path: String,body: Data?,bearer: String?) async throws -> BackendHTTPResponse {
        if method == "GET" {
            if path == "/api/tasks" { return .init(status:200,body:try JSONSerialization.data(withJSONObject:["tasks":tasks,"active":"7"])) }
            return .init(status:200,body:Data("{\"items\":[\(rows.joined(separator:","))],\"total\":\(rows.count),\"page\":1,\"size\":20}".utf8))
        }
        writes.append((method,path,body))
        if hold { return try await withCheckedThrowingContinuation { held.append($0) } }
        guard !replies.isEmpty else { throw BackendAPIError.status(503) }; return replies.removeFirst()
    }
}
final class TaskArchiveWorkspaceTests: XCTestCase {
    private func row(_ id: Int64 = 17,task: Int64 = 7,state: String = "ready") -> String {
        """
        {"id":\(id),"task_id":\(task),"state":"\(state)","phase":"queued","progress":0,"format_version":3,"original_size":0,"compressed_size":0,"task_name":"literal 中文 한국어 e\\u0301","task_description":"","task_goal":"","original_status":"paused","remaining_timeout_seconds":0,"requested_at":"r","created_at":"c","updated_at":"u"}
        """
    }
    private func reply(_ body: String,status: Int = 202) -> BackendHTTPResponse { .init(status:status,body:Data(body.utf8)) }
    private func record(_ id: Int64 = 17,task: Int64 = 7,state: String = "ready") throws -> TaskArchiveRecord {
        try BackendJSONCoding.decode(TaskArchiveRecord.self,from:Data(row(id,task:task,state:state).utf8))
    }
    @MainActor private func reached(_ condition: () -> Bool) async throws {
        for _ in 0..<10000 { if condition() { return }; await Task.yield() }; XCTFail("Missing controlled suspension"); throw CancellationError()
    }
    @MainActor private func make() async throws -> (ArchiveActionAPI,TaskArchiveWorkspace,TaskStore,TaskArchiveStore) {
        let api = ArchiveActionAPI()
        let path = URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("ArtexCoreTests/Fixtures/task-contract.json")
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with:Data(contentsOf:path)) as? [String:Any]); let seed = try XCTUnwrap(object["task"] as? [String:Any])
        api.tasks = [7,8,9].map { id in var r = seed; r["id"] = String(id); r["status"] = id == 9 ? "running" : "paused"; r["archive_blocked_by_task_id"] = id == 8 ? "7" : ""; return r }
        api.rows = [row(),row(18,task:8),row(19,task:9,state:"restoring")]
        let live = TaskStore(service:TaskService(client:api)); await live.refreshList()
        let cold = TaskArchiveStore(service:TaskArchiveService(client:api)); await cold.refresh()
        return (api,TaskArchiveWorkspace(store:live,archives:cold,service:TaskArchiveService(client:api)),live,cold)
    }
    @MainActor func testSingleArchiveReceiptIsNotCompletionAndCannotRepeatContext() async throws {
        let (api,model,live,cold) = try await make(); let tasks = try XCTUnwrap(live.list.value)
        XCTAssertFalse(model.beginArchive([tasks[1]],batch:false)); XCTAssertTrue(model.beginArchive([tasks[0]],batch:false))
        let id = try XCTUnwrap(model.context).id; api.replies = [reply(row(state:"archive_queued"))]
        let finished = await model.submit(contextID:id); XCTAssertTrue(finished)
        XCTAssertEqual(model.items.map(\.state),[.accepted]); XCTAssertEqual(live.list.value?.count,3); XCTAssertTrue(live.list.isStale)
        XCTAssertTrue(cold.pendingRestoreIDs.isEmpty); XCTAssertFalse(live.isMutating); XCTAssertFalse(cold.isMutating)
        _ = await model.submit(contextID:id); XCTAssertEqual(api.writes.count,1); XCTAssertEqual(api.writes[0].1,"/api/tasks/7/archive")
    }
    @MainActor func testBulkArchiveUsesServerOrderAndPartialResultCallback() async throws {
        let (api,model,live,_) = try await make(); var callbacks = 0; model.onReceipt = { _ in callbacks += 1 }
        XCTAssertTrue(model.beginArchive(try XCTUnwrap(live.list.value),batch:true)); let owner = try XCTUnwrap(model.context)
        XCTAssertEqual(owner.taskIDs,["7","8"])
        api.replies = [reply(#"{"items":[{"id":"8","ok":false,"queued":false,"error":"private worker"},{"id":"7","ok":true,"queued":true,"archive_id":17}]}"#)]
        _ = await model.submit(contextID:owner.id); XCTAssertEqual(model.items.map(\.id),["8","7"])
        XCTAssertEqual(model.items.map(\.state),[.rejected,.accepted]); XCTAssertEqual(callbacks,1)
        XCTAssertEqual(api.writes[0].1,"/api/tasks/archive/batch"); XCTAssertFalse(String(describing:model.items).contains("private"))
    }
    @MainActor func testRestoreBatchRegistersOnlyAcceptedCapturedTasksAndClearsSelection() async throws {
        let (api,model,_,cold) = try await make(); cold.setAll(selected:true,owner:cold.viewOwner)
        XCTAssertTrue(model.begin(.restore,archives:try XCTUnwrap(cold.list.value).items)); let owner = try XCTUnwrap(model.context).id
        api.replies = [reply(#"{"items":[{"id":"18","ok":false,"queued":false,"archive_id":18},{"id":"17","ok":true,"queued":true,"archive_id":17}]}"#)]
        _ = await model.submit(contextID:owner)
        XCTAssertEqual(cold.pendingRestoreIDs,Set([17])); XCTAssertTrue(cold.removedAfterRestoreIDs.isEmpty)
        XCTAssertTrue(cold.selectedIDs.isEmpty); XCTAssertEqual(cold.list.value?.items.count,3)
        XCTAssertEqual(api.writes[0].1,"/api/task-archives/restore/batch")
    }
    @MainActor func testSingleColdTaskMismatchIsUnknownAndNeedsCapturedAcknowledgement() async throws {
        let (api,model,_,_) = try await make(); let r = try record()
        XCTAssertTrue(model.begin(.delete,archives:[r])); let id = try XCTUnwrap(model.context).id
        api.replies = [reply(row(task:99,state:"delete_queued"))]; _ = await model.submit(contextID:id)
        XCTAssertEqual(model.items.map(\.state),[.unconfirmed]); XCTAssertEqual(model.uncertainTaskIDs,Set(["7"]))
        XCTAssertEqual(model.uncertainArchiveIDs,Set([17])); model.close(contextID:id); XCTAssertFalse(model.begin(.restore,archives:[r]))
        model.requestAcknowledgement(); let ack = try XCTUnwrap(model.acknowledgement).id
        model.resolveAcknowledgement(id:UUID(),accept:true); XCTAssertNotNil(model.acknowledgement)
        model.resolveAcknowledgement(id:ack,accept:true); XCTAssertTrue(model.uncertainTaskIDs.isEmpty)
        XCTAssertTrue(model.begin(.restore,archives:[r])); XCTAssertEqual(api.writes.count,1)
    }
    @MainActor func testHeldWriteExcludesOtherMutationsAndResetWaitsForTerminal() async throws {
        let (api,model,live,cold) = try await make(); XCTAssertTrue(model.begin(.restore,archives:[try record()]))
        let id = try XCTUnwrap(model.context).id; api.hold = true; let work = Task { await model.submit(contextID:id) }
        try await reached { api.held.count == 1 }; XCTAssertTrue(live.isMutating); XCTAssertTrue(cold.isMutating)
        XCTAssertNil(live.beginBulkMutation()); XCTAssertNil(live.beginCategoryMutation()); XCTAssertFalse(cold.configure(page:2,size:20,query:"",state:nil))
        model.reset(); live.reset(); cold.reset(); XCTAssertTrue(model.isSubmitting); XCTAssertTrue(live.isMutating); XCTAssertTrue(cold.isMutating)
        XCTAssertFalse(model.begin(.delete,archives:[try record()])); api.held[0].resume(returning:reply(row(state:"restore_queued")))
        let finished = await work.value; XCTAssertFalse(finished); XCTAssertFalse(model.isSubmitting); XCTAssertFalse(live.isMutating); XCTAssertFalse(cold.isMutating)
        XCTAssertTrue(model.items.isEmpty); XCTAssertTrue(cold.pendingRestoreIDs.isEmpty); XCTAssertTrue(model.uncertainTaskIDs.isEmpty)
    }
    @MainActor func testSuspendAfterDispatchCapturesUnknownAndNeverReplays() async throws {
        let (api,model,live,_) = try await make(); XCTAssertTrue(model.beginArchive([try XCTUnwrap(live.list.value?.first)],batch:false))
        let id = try XCTUnwrap(model.context).id; api.hold = true; let work = Task { await model.submit(contextID:id) }
        try await reached { api.held.count == 1 }; model.suspend(); api.held[0].resume(returning:reply(row(state:"archive_queued")))
        _ = await work.value; XCTAssertEqual(model.items.map(\.state),[.unconfirmed]); XCTAssertEqual(model.uncertainTaskIDs,Set(["7"]))
        XCTAssertEqual(api.writes.count,1); XCTAssertNil(model.context); XCTAssertFalse(live.isMutating)
    }
    @MainActor func testExplicitRetriesSelectEachFailedOperationAndOnlyRestoreTracks() async throws {
        for (failed,queued,path) in [("archive_failed","archive_queued","/api/tasks/7/archive"),("restore_failed","restore_queued","/api/task-archives/17/restore"),("delete_failed","delete_queued","/api/task-archives/17")] {
            let (api,model,_,cold) = try await make(); XCTAssertTrue(model.begin(.retry,archives:[try record(state:failed)]))
            api.replies = [reply(row(state:queued))]; _ = await model.submit(contextID:try XCTUnwrap(model.context).id)
            XCTAssertEqual(api.writes.first?.1,path); XCTAssertEqual(model.items.map(\.state),[.accepted])
            XCTAssertEqual(cold.pendingRestoreIDs,failed == "restore_failed" ? Set([17]) : [])
        }
    }
    @MainActor func testRejectedStatusesAndMalformed202AreDistinct() async throws {
        for status in [400,401,403,404,409,413,422,500,202] {
            let (api,model,_,_) = try await make(); XCTAssertTrue(model.begin(.delete,archives:[try record()]))
            api.replies = [reply("{}",status:status)]; _ = await model.submit(contextID:try XCTUnwrap(model.context).id)
            XCTAssertEqual(model.items.first?.state,[500,202].contains(status) ? .unconfirmed : .rejected)
        }
    }
    @MainActor func testQueuedCancellationBeforeDispatchAndInvalidContextDoNotSend() async throws {
        let (api,model,_,_) = try await make(); XCTAssertTrue(model.begin(.delete,archives:[try record()])); let id = try XCTUnwrap(model.context).id
        _ = await model.submit(contextID:UUID()); XCTAssertTrue(api.writes.isEmpty)
        model.submitFromUI(contextID:id); model.cancel(contextID:id)
        try await reached { !model.isSubmitting }; XCTAssertEqual(model.items.map(\.state),[.notStarted]); XCTAssertTrue(api.writes.isEmpty)
    }
}
