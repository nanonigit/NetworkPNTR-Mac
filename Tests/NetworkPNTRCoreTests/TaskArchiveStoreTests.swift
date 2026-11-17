import XCTest
@testable import NetworkPNTRCore

@MainActor private final class ArchiveReadAPI: BackendJSONTransport {
    var calls: [String] = []
    var replies: [BackendHTTPResponse] = []
    var hold = false
    var held: [CheckedContinuation<BackendHTTPResponse,Error>] = []
    func send(method: String,path: String,body: Data?,bearer: String?) async throws -> BackendHTTPResponse {
        XCTAssertEqual(method,"GET"); XCTAssertNil(body); calls.append(path)
        if hold { return try await withCheckedThrowingContinuation { held.append($0) } }
        guard !replies.isEmpty else { throw BackendAPIError.status(503) }
        return replies.removeFirst()
    }
}
final class TaskArchiveStoreTests: XCTestCase {
    private func row(_ id: Int64 = 7, task: Int64 = 8, state: String = "ready") -> String {
        """
        {"id":\(id),"task_id":\(task),"state":"\(state)","phase":"queued","progress":0,"format_version":3,"original_size":0,"compressed_size":0,"task_name":"\\ufeffe\\u0301 中文 한국어","task_description":"literal","task_goal":"g","original_status":"paused","remaining_timeout_seconds":0,"requested_at":"r","created_at":"c","updated_at":"u"}
        """
    }
    private func reply(_ body: String = "{}",status: Int = 200) -> BackendHTTPResponse { .init(status:status,body:Data(body.utf8)) }
    private func page(_ rows: [String], page: Int = 1, size: Int = 20) -> BackendHTTPResponse {
        reply("{\"items\":[\(rows.joined(separator:","))],\"total\":100,\"page\":\(page),\"size\":\(size)}")
    }
    private func receipt(_ id: Int64 = 7, task: Int64 = 8, state: String = "restore_queued") throws -> TaskArchiveRecord {
        try BackendJSONCoding.decode(TaskArchiveRecord.self,from:Data(row(id,task:task,state:state).utf8))
    }
    @MainActor private func reached(_ condition: () -> Bool) async throws {
        for _ in 0..<10000 { if condition() { return }; await Task.yield() }
        XCTFail("Missing controlled suspension"); throw CancellationError()
    }
    @MainActor func testDefaultsPageLocalSelectionAndStaleFailure() async throws {
        let api = ArchiveReadAPI(), store = TaskArchiveStore(service:TaskArchiveService(client:ArchiveReadAPI()))
        XCTAssertEqual(store.page,1); XCTAssertEqual(store.size,20); XCTAssertEqual(store.query,""); XCTAssertNil(store.state)
        let model = TaskArchiveStore(service:TaskArchiveService(client:api))
        api.replies = [page([row(),row(9,state:"restoring")])]; await model.refresh()
        model.setSelected(7,selected:true,owner:model.viewOwner); model.setSelected(9,selected:true,owner:model.viewOwner)
        XCTAssertEqual(model.selectedIDs,Set([7])); XCTAssertFalse(model.list.isStale)
        api.replies = [reply(status:503)]; await model.refresh()
        XCTAssertTrue(model.list.isStale); XCTAssertNotNil(model.list.failure); XCTAssertEqual(model.selectedIDs,Set([7]))
        api.replies = [page([row(9)])]; await model.refresh(); XCTAssertTrue(model.selectedIDs.isEmpty); XCTAssertNil(model.list.failure)
        let old = model.viewOwner
        XCTAssertTrue(model.configure(page:2,size:10,query:"a+ 中文 e\u{301}",state:"ready"))
        XCTAssertNil(model.list.value); XCTAssertNil(model.selectedID); model.setSelected(9,selected:true,owner:old)
        XCTAssertTrue(model.selectedIDs.isEmpty); api.replies = [page([],page:2,size:10)]; await model.refresh()
        XCTAssertTrue(try XCTUnwrap(api.calls.last).contains("q=a%2B"))
        XCTAssertFalse(model.configure(page:0,size:10,query:"",state:nil)); XCTAssertEqual(model.page,2)
        XCTAssertFalse(model.configure(page:Int64.max,size:100,query:"",state:nil))
        XCTAssertFalse(model.configure(page:1,size:20,query:String(repeating:"a",count:4097),state:nil))
        XCTAssertEqual(model.page,2)
    }
    @MainActor func testOldFilterAndOldDetailCannotOverwriteReplacement() async throws {
        let api = ArchiveReadAPI(); let model = TaskArchiveStore(service:TaskArchiveService(client:api)); api.hold = true
        let first = Task { await model.refresh() }; try await reached { api.held.count == 1 }
        XCTAssertTrue(model.configure(page:2,size:20,query:"literal",state:nil))
        let next = Task { await model.refresh() }; try await reached { api.held.count == 2 }
        api.held[1].resume(returning:page([row(9)],page:2)); await next.value
        api.held[0].resume(returning:page([row()])); await first.value
        XCTAssertEqual(model.list.value?.items.map(\.id),[9]); XCTAssertFalse(model.isRefreshing)
        let detail = Task { await model.select(9) }; try await reached { api.held.count == 3 }
        await model.select(nil); api.held[2].resume(returning:reply(row(9))); await detail.value
        XCTAssertNil(model.detail.value); XCTAssertNil(model.selectedID)
    }
    @MainActor func testReceipt404OnlyReconcilesCapturedAcceptedOwner() async throws {
        let api = ArchiveReadAPI(); let model = TaskArchiveStore(service:TaskArchiveService(client:api)); let owner = model.sessionOwner
        XCTAssertFalse(model.observeAcceptedRestore(try receipt(state:"ready"),owner:owner))
        XCTAssertFalse(model.observeAcceptedRestore(try receipt(),owner:UUID()))
        let revision = model.reconciliationRevision
        XCTAssertTrue(model.observeAcceptedRestore(try receipt(9007199254740993),owner:owner))
        api.replies = [page([]),reply(status:503)]; await model.refresh()
        XCTAssertEqual(model.pendingRestoreIDs,Set([9007199254740993])); XCTAssertNotNil(model.reconciliationFailure)
        XCTAssertEqual(model.reconciliationRevision,revision)
        api.replies = [page([]),reply(status:404)]; await model.refresh()
        XCTAssertTrue(model.pendingRestoreIDs.isEmpty); XCTAssertEqual(model.removedAfterRestoreIDs,Set([9007199254740993]))
        XCTAssertNotEqual(model.reconciliationRevision,revision); XCTAssertNil(model.reconciliationFailure)
        api.replies = [reply(status:404)]; await model.select(12)
        XCTAssertNotNil(model.detail.failure); XCTAssertEqual(model.removedAfterRestoreIDs,Set([9007199254740993]))
        XCTAssertTrue(api.calls.contains("/api/task-archives/9007199254740993"))
    }
    @MainActor func testPendingIdentityMismatchAndAuthFailureNeverConsumeReceipt() async throws {
        let api = ArchiveReadAPI(); let model = TaskArchiveStore(service:TaskArchiveService(client:api))
        XCTAssertTrue(model.observeAcceptedRestore(try receipt(),owner:model.sessionOwner))
        api.replies = [page([]),reply(row(task:99))]; await model.refresh()
        XCTAssertEqual(model.pendingRestoreIDs,Set([7])); XCTAssertNotNil(model.reconciliationFailure)
        XCTAssertTrue(model.observeAcceptedRestore(try receipt(9),owner:model.sessionOwner))
        api.replies = [page([]),reply(status:401)]; let count = api.calls.count; await model.refresh()
        XCTAssertEqual(api.calls.count-count,2); XCTAssertEqual(model.pendingRestoreIDs,Set([7,9]))
        XCTAssertTrue(model.removedAfterRestoreIDs.isEmpty)
    }
    @MainActor func testReplacedReceiptSurvivesOld404AndListFailureStillReconciles() async throws {
        let api = ArchiveReadAPI(); let model = TaskArchiveStore(service:TaskArchiveService(client:api))
        XCTAssertTrue(model.observeAcceptedRestore(try receipt(),owner:model.sessionOwner))
        api.hold = true; let cycle = Task { await model.refresh() }; try await reached { api.held.count == 1 }
        api.held[0].resume(returning:reply(status:503)); try await reached { api.held.count == 2 }
        XCTAssertTrue(model.observeAcceptedRestore(try receipt(),owner:model.sessionOwner))
        api.held[1].resume(returning:reply(status:404)); await cycle.value
        XCTAssertEqual(model.pendingRestoreIDs,Set([7])); XCTAssertTrue(model.removedAfterRestoreIDs.isEmpty)
        api.hold = false; api.replies = [reply(status:503),reply(status:404)]; await model.refresh()
        XCTAssertNotNil(model.list.failure); XCTAssertTrue(model.pendingRestoreIDs.isEmpty); XCTAssertEqual(model.removedAfterRestoreIDs,Set([7]))
    }
    @MainActor func testStopRetainsPendingButResetRotatesSessionAndDiscardsReads() async throws {
        let api = ArchiveReadAPI(); let model = TaskArchiveStore(service:TaskArchiveService(client:api)); let session = model.sessionOwner
        XCTAssertTrue(model.observeAcceptedRestore(try receipt(),owner:session))
        api.hold = true; let cycle = Task { await model.refresh() }; try await reached { api.held.count == 1 }
        model.stop(); XCTAssertFalse(model.isRefreshing); XCTAssertEqual(model.pendingRestoreIDs,Set([7]))
        api.held[0].resume(returning:page([row()])); await cycle.value; XCTAssertNil(model.list.value)
        let again = Task { await model.refresh() }; try await reached { api.held.count == 2 }
        model.reset(); api.held[1].resume(returning:page([row()])); await again.value
        XCTAssertNil(model.list.value); XCTAssertNotEqual(model.sessionOwner,session); XCTAssertTrue(model.pendingRestoreIDs.isEmpty)
        XCTAssertFalse(model.observeAcceptedRestore(try receipt(),owner:session)); XCTAssertEqual(api.held.count,2)
    }
    @MainActor func testPollingSingleFlightTwoSecondsAndStopDoesNotEndNewLoop() async throws {
        let api = ArchiveReadAPI(); var sleeps: [CheckedContinuation<Void,Error>] = []; var durations: [Duration] = []
        let model = TaskArchiveStore(service:TaskArchiveService(client:api),sleep:{ duration in
            durations.append(duration); try await withCheckedThrowingContinuation { sleeps.append($0) }
        })
        api.replies = [page([])]; let first = Task { await model.run() }; try await reached { sleeps.count == 1 }
        XCTAssertTrue(model.isPolling); await model.run(); XCTAssertEqual(api.calls.count,1)
        model.stop(); api.replies = [page([])]; let next = Task { await model.run() }; try await reached { sleeps.count == 2 }
        sleeps[0].resume(); await first.value; XCTAssertTrue(model.isPolling)
        model.stop(); sleeps[1].resume(); await next.value; XCTAssertFalse(model.isPolling)
        XCTAssertEqual(durations,[.seconds(2),.seconds(2)])
    }
    @MainActor func testCancelledCycleDoesNotApplyOrProbePendingAndOverlapIsSuppressed() async throws {
        let api = ArchiveReadAPI(); let model = TaskArchiveStore(service:TaskArchiveService(client:api))
        XCTAssertTrue(model.observeAcceptedRestore(try receipt(),owner:model.sessionOwner)); api.hold = true
        let cycle = Task { await model.refresh() }; try await reached { api.held.count == 1 }
        await model.refresh(); XCTAssertEqual(api.calls.count,1); cycle.cancel()
        api.held[0].resume(returning:page([row()])); await cycle.value
        XCTAssertNil(model.list.value); XCTAssertFalse(model.isRefreshing); XCTAssertEqual(model.pendingRestoreIDs,Set([7]))
    }
    @MainActor func testExactUnicodeFiltersAndSelectionReconcileOnlyAfterSuccess() async throws {
        let api = ArchiveReadAPI(); let model = TaskArchiveStore(service:TaskArchiveService(client:api))
        api.replies = [page([row(),row(9),row(10,state:"archiving")])]; await model.refresh()
        model.setAll(selected:true,owner:model.viewOwner); XCTAssertEqual(model.selectedIDs,Set([7,9]))
        model.setAll(selected:false,owner:UUID()); XCTAssertEqual(model.selectedIDs,Set([7,9]))
        api.replies = [page([row(state:"restoring"),row(9)])]; await model.refresh()
        XCTAssertEqual(model.selectedIDs,Set([9])); model.setAll(selected:false,owner:model.viewOwner); XCTAssertTrue(model.selectedIDs.isEmpty)
        XCTAssertTrue(model.configure(page:1,size:20,query:"é",state:"é")); let first = model.viewOwner
        XCTAssertTrue(model.configure(page:1,size:20,query:"e\u{301}",state:"e\u{301}")); XCTAssertNotEqual(first,model.viewOwner)
        XCTAssertEqual(Array(model.query.utf8),Array("e\u{301}".utf8)); let same = model.viewOwner
        XCTAssertTrue(model.configure(page:1,size:20,query:"e\u{301}",state:"e\u{301}")); XCTAssertEqual(same,model.viewOwner)
        XCTAssertFalse(model.configure(page:1,size:101,query:"",state:nil))
        XCTAssertFalse(model.configure(page:1,size:20,query:"",state:String(repeating:"a",count:129)))
    }
    @MainActor func testSelectedDetailPreservesStaleValueAndStopInvalidatesLateDetail() async throws {
        let api = ArchiveReadAPI(); let model = TaskArchiveStore(service:TaskArchiveService(client:api))
        api.replies = [reply(row())]; await model.select(7); XCTAssertEqual(model.detail.value?.id,7)
        api.replies = [reply(status:503)]; await model.refreshSelected()
        XCTAssertTrue(model.detail.isStale); XCTAssertEqual(model.detail.value?.id,7); XCTAssertNotNil(model.detail.failure)
        await model.select(-1); XCTAssertEqual(model.selectedID,7)
        api.hold = true; let work = Task { await model.refreshSelected() }; try await reached { api.held.count == 1 }
        model.stop(); api.held[0].resume(returning:reply(row(state:"restoring"))); await work.value
        XCTAssertEqual(model.detail.value?.state,"ready"); XCTAssertTrue(model.detail.isStale); XCTAssertFalse(model.detail.isLoading)
    }
    @MainActor func testPending200AndFailedStateDoNotClaimRemovalAndCancelledProbeIsDiscarded() async throws {
        let api = ArchiveReadAPI(); let model = TaskArchiveStore(service:TaskArchiveService(client:api))
        XCTAssertTrue(model.observeAcceptedRestore(try receipt(),owner:model.sessionOwner)); let revision = model.reconciliationRevision
        api.replies = [page([]),reply(row(state:"restore_failed"))]; await model.refresh()
        XCTAssertEqual(model.pendingRestoreIDs,Set([7])); XCTAssertTrue(model.removedAfterRestoreIDs.isEmpty)
        XCTAssertEqual(model.reconciliationRevision,revision); XCTAssertNil(model.reconciliationFailure)
        api.hold = true; let cycle = Task { await model.refresh() }; try await reached { api.held.count == 1 }
        api.held[0].resume(returning:page([])); try await reached { api.held.count == 2 }
        cycle.cancel(); api.held[1].resume(returning:reply(status:404)); await cycle.value
        XCTAssertEqual(model.pendingRestoreIDs,Set([7])); XCTAssertEqual(model.reconciliationRevision,revision)
    }
    @MainActor func testPollingSleepFailureAndPrecancelledReadsTerminateWithoutRequests() async throws {
        let api = ArchiveReadAPI(); let model = TaskArchiveStore(service:TaskArchiveService(client:api),sleep:{ _ in throw CancellationError() })
        api.replies = [page([])]; await model.run(); XCTAssertFalse(model.isPolling); XCTAssertEqual(api.calls.count,1)
        let work = Task { await model.refresh(); await model.select(9); await model.run() }; work.cancel(); await work.value
        XCTAssertEqual(api.calls.count,1); XCTAssertNil(model.selectedID); XCTAssertFalse(model.isPolling)
    }

    @MainActor func testManualSelectionWinsOverCycleDetailAndPrecancelledSelectPreservesIt() async throws {
        let api = ArchiveReadAPI(); let model = TaskArchiveStore(service:TaskArchiveService(client:api))
        api.replies = [reply(row())]; await model.select(7)
        api.hold = true; let cycle = Task { await model.refresh() }; try await reached { api.held.count == 1 }
        api.held[0].resume(returning:page([row(),row(9)])); try await reached { api.held.count == 2 }
        let selection = Task { await model.select(9) }; try await reached { api.held.count == 3 }
        api.held[2].resume(returning:reply(row(9))); await selection.value
        api.held[1].resume(returning:reply(row())); await cycle.value
        XCTAssertEqual(model.selectedID,9); XCTAssertEqual(model.detail.value?.id,9); XCTAssertFalse(model.detail.isStale)
        let cancelled = Task { await model.select(nil) }; cancelled.cancel(); await cancelled.value
        XCTAssertEqual(model.selectedID,9); XCTAssertEqual(model.detail.value?.id,9); XCTAssertEqual(api.calls.count,4)
    }

}
