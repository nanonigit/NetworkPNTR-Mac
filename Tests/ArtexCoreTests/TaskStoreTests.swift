import XCTest
@testable import ArtexCore

final class TaskStoreTests: XCTestCase {
    private struct TestFailure: Error {}
    private func task(_ id: String = "7", name: String = "literal 中文 한국어") throws -> [String: Any] {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "task-contract", withExtension: "json", subdirectory: "Fixtures"))
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        var value = try XCTUnwrap(root["task"] as? [String: Any]); value["id"] = id; value["name"] = name
        return value
    }
    private func draft() -> TaskCreateDraft { var d = TaskCreateDraft(); d.description = "d"; d.goal = "g"; return d }
    private func deletion(_ id: String = "7") -> [String: Any] {
        ["deleted": id, "assets_deleted": 0, "assets_detached": 1, "traffic_deleted": 0,
         "files_deleted": false, "findings_deleted": 0, "llm_records_deleted": 0, "cleanup_warning": "private-secret"]
    }
    private func confirmed<T>(_ result: TaskMutationOutcome<T>) throws -> T {
        guard case let .confirmed(value) = result else { XCTFail("Expected confirmed mutation"); throw TestFailure() }
        return value
    }
    @MainActor private func reached(_ condition: () -> Bool) async throws {
        for _ in 0..<10_000 { if condition() { return }; await Task.yield() }
        XCTFail("Controlled operation did not reach suspension"); throw TestFailure()
    }
    @MainActor func testReadsRetainCachedDataOnFailureAndSelectWithoutActivation() async throws {
        let api = ChatTestTransport(); let store = TaskStore(service: TaskService(client: api))
        try api.enqueue(["tasks": [task()], "active": "7"]); await store.refreshList()
        XCTAssertEqual(store.list.value?.first?.id, "7"); XCTAssertEqual(store.activeID, "7"); XCTAssertFalse(store.list.isStale)
        try api.enqueue(["error": "private-secret"], status: 503); await store.refreshList()
        XCTAssertEqual(store.list.value?.first?.name, "literal 中文 한국어"); XCTAssertTrue(store.list.isStale); XCTAssertNotNil(store.list.failure)
        try api.enqueue(task()); await store.select(id: "0007")
        XCTAssertEqual(store.selectedID, "7"); XCTAssertEqual(store.detail.value?.id, "7")
        await store.select(id: "bad/path"); XCTAssertEqual(store.selectedID, "7"); XCTAssertNotNil(store.detail.failure)
        try api.enqueue(task(name: "fresh")); await store.select(id: "7")
        XCTAssertEqual(store.detail.value?.name, "fresh"); XCTAssertNil(store.detail.failure)
        await store.select(id: nil); XCTAssertNil(store.detail.value); XCTAssertNil(store.selectedID)
        XCTAssertEqual(api.calls.count, 4); XCTAssertTrue(api.calls.allSatisfy { $0.method == "GET" }); XCTAssertFalse(api.calls.contains { $0.path == "/api/active" })
    }
    @MainActor func testSelectionResponseReorderingCannotShowAnotherTask() async throws {
        let api = ChatTestTransport(); let store = TaskStore(service: TaskService(client: api))
        var replies: [String: CheckedContinuation<BackendHTTPResponse, any Error>] = [:]
        api.handler = { call in try await withCheckedThrowingContinuation { replies[call.path] = $0 } }
        let old = Task { await store.select(id: "7") }; try await reached { replies["/api/tasks/7"] != nil }
        let current = Task { await store.select(id: "8") }; try await reached { replies["/api/tasks/8"] != nil }
        XCTAssertNil(store.detail.value); XCTAssertEqual(store.selectedID, "8")
        try XCTUnwrap(replies.removeValue(forKey: "/api/tasks/7")).resume(returning: ChatTestTransport.response(task()))
        await old.value; XCTAssertTrue(store.detail.isLoading); XCTAssertNil(store.detail.value)
        try XCTUnwrap(replies.removeValue(forKey: "/api/tasks/8")).resume(returning: ChatTestTransport.response(task("8")))
        await current.value; XCTAssertEqual(store.detail.value?.id, "8"); XCTAssertFalse(store.detail.isLoading)
    }
    @MainActor func testConfirmedCreateSurvivesRefreshFailureAndDoesNotSelectOrRetry() async throws {
        let api = ChatTestTransport(); let store = TaskStore(service: TaskService(client: api))
        try api.enqueue(task(), status: 201); try api.enqueue(["error": "private-secret"], status: 503)
        let result = try confirmed(await store.create(draft()))
        XCTAssertEqual(result.id, "7"); XCTAssertNil(store.selectedID); XCTAssertNotNil(store.list.failure)
        guard case .created(let record) = store.lastConfirmation else { return XCTFail("Missing confirmation") }
        XCTAssertEqual(record.id, "7"); XCTAssertNil(store.mutationFailure); XCTAssertFalse(store.mutationUncertain)
        XCTAssertEqual(api.calls.map(\.method), ["POST", "GET"])
    }
    @MainActor func testDeleteInvalidatesEarlierReadAndClearsOnlyDeletedOwner() async throws {
        let api = ChatTestTransport(); let store = TaskStore(service: TaskService(client: api))
        try api.enqueue(["tasks": [task(), task("8")], "active": "7"]); await store.refreshList()
        try api.enqueue(task()); await store.select(id: "7")
        var earlier: CheckedContinuation<BackendHTTPResponse, any Error>?
        api.handler = { _ in try await withCheckedThrowingContinuation { earlier = $0 } }
        let read = Task { await store.refreshList() }; try await reached { earlier != nil }
        api.handler = nil
        try api.enqueue(deletion()); try api.enqueue(["error": "private-secret"], status: 503)
        let result = try confirmed(await store.delete(id: "7"))
        XCTAssertTrue(result.hasCleanupWarning); XCTAssertEqual(store.list.value?.map(\.id), ["8"])
        XCTAssertNil(store.activeID); XCTAssertNil(store.selectedID); XCTAssertNil(store.detail.value)
        try XCTUnwrap(earlier).resume(returning: ChatTestTransport.response(["tasks": [task(), task("8")], "active": "7"]))
        await read.value; XCTAssertEqual(store.list.value?.map(\.id), ["8"]); XCTAssertTrue(store.list.isStale)
        XCTAssertEqual(api.calls.filter { $0.method == "DELETE" }.count, 1)
    }
    @MainActor func testMutationGateSurvivesStopAndResetUntilRealCompletion() async throws {
        let api = ChatTestTransport(); let store = TaskStore(service: TaskService(client: api))
        var reply: CheckedContinuation<BackendHTTPResponse, any Error>?
        api.handler = { _ in try await withCheckedThrowingContinuation { reply = $0 } }
        let operation = Task { await store.create(draft()) }; try await reached { reply != nil }
        store.stop(); XCTAssertTrue(store.isMutating)
        guard case .notStarted = await store.create(draft()) else { return XCTFail("Duplicate mutation started") }
        store.reset(); XCTAssertTrue(store.isMutating); XCTAssertNil(store.list.value); XCTAssertNil(store.lastConfirmation)
        guard case .notStarted = await store.delete(id: "7") else { return XCTFail("Reset released gate early") }
        try XCTUnwrap(reply).resume(returning: ChatTestTransport.response(task(), status: 201))
        guard case .discarded = await operation.value else { return XCTFail("Prior session result exposed") }
        XCTAssertFalse(store.isMutating); XCTAssertNil(store.lastConfirmation); XCTAssertEqual(api.calls.count, 1)
    }
    @MainActor func testUnconfirmedCancellationAndTypedRejectionNeverAutoRetry() async throws {
        let api = ChatTestTransport(); let store = TaskStore(service: TaskService(client: api))
        var reply: CheckedContinuation<BackendHTTPResponse, any Error>?
        api.handler = { _ in try await withCheckedThrowingContinuation { reply = $0 } }
        let operation = Task { await store.create(draft()) }; try await reached { reply != nil }; operation.cancel()
        try XCTUnwrap(reply).resume(returning: ChatTestTransport.response(task(), status: 201))
        guard case .unconfirmed = await operation.value else { return XCTFail("Cancellation treated as rollback") }
        XCTAssertTrue(store.mutationUncertain); XCTAssertNotNil(store.mutationFailure); XCTAssertNil(store.lastConfirmation); XCTAssertEqual(api.calls.count, 1)
        guard case .rejected = await store.update(id: "bad", patch: .init(pinned: true)) else { return XCTFail("Invalid input sent") }
        XCTAssertFalse(store.mutationUncertain); XCTAssertEqual(api.calls.count, 1)
    }
    @MainActor func testMetadataControlAndPartialBatchKeepConfirmationAndAggregates() async throws {
        let api = ChatTestTransport(); let store = TaskStore(service: TaskService(client: api))
        try api.enqueue(["tasks": [task()], "active": "7"]); await store.refreshList()
        try api.enqueue(task(name: "renamed")); try api.enqueue([:], status: 503)
        let updated = try confirmed(await store.update(id: "7", patch: .init(name: "renamed"))); XCTAssertEqual(updated.name, "renamed")
        XCTAssertEqual(store.list.value?.first?.tokens.inputTokens, 9_007_199_254_740_993)
        guard case .updated = store.lastConfirmation else { return XCTFail("Missing metadata receipt") }
        try api.enqueue(["id": "7", "paused": true, "queued": false, "status": "paused"]); try api.enqueue([:], status: 503)
        _ = try confirmed(await store.control(id: "7", action: .pause))
        guard case .controlled = store.lastConfirmation else { return XCTFail("Missing control receipt") }
        try api.enqueue(["items": [["id": "7", "ok": true, "status": "running"], ["id": "8", "ok": false, "error": "private-secret"]]])
        try api.enqueue([:], status: 503)
        let batch = try confirmed(await store.controlBatch(ids: ["7", "8"], action: .resume)); XCTAssertFalse(batch[1].ok)
        guard case .batchControlled(let items) = store.lastConfirmation else { return XCTFail("Missing batch receipt") }
        XCTAssertEqual(items.map(\.id), ["7", "8"]); XCTAssertFalse(String(describing: items).contains("private-secret"))
        XCTAssertEqual(api.calls.filter { $0.method != "GET" }.count, 3)
    }
    @MainActor func testStopSuppressesReadButRetainsStoppedOperationConfirmationWithoutRefresh() async throws {
        let api = ChatTestTransport(); let store = TaskStore(service: TaskService(client: api))
        var reply: CheckedContinuation<BackendHTTPResponse, any Error>?
        api.handler = { _ in try await withCheckedThrowingContinuation { reply = $0 } }
        let read = Task { await store.refreshList() }; try await reached { reply != nil }; store.stop()
        try XCTUnwrap(reply).resume(returning: ChatTestTransport.response(["tasks": [task()], "active": "7"]))
        await read.value; XCTAssertNil(store.list.value); XCTAssertFalse(store.list.isLoading)
        reply = nil
        let change = Task { await store.create(draft()) }; try await reached { reply != nil }; store.stop()
        try XCTUnwrap(reply).resume(returning: ChatTestTransport.response(task(), status: 201))
        _ = try confirmed(await change.value); XCTAssertNotNil(store.lastConfirmation); XCTAssertEqual(api.calls.count, 2)
    }
    @MainActor func testPollHasSingleOwnerTenSecondCadenceAndOldOwnerCannotStopNewOne() async throws {
        let api = ChatTestTransport(); var pauses: [CheckedContinuation<Void, any Error>] = []; var durations: [Duration] = []
        let store = TaskStore(service: TaskService(client: api), sleep: { delay in
            durations.append(delay); try await withCheckedThrowingContinuation { pauses.append($0) }
        })
        try api.enqueue(["tasks": [], "active": ""])
        let first = Task { await store.run() }; try await reached { pauses.count == 1 }
        await store.run(); XCTAssertEqual(api.calls.count, 1); XCTAssertTrue(store.isPolling)
        store.stop(); try api.enqueue(["tasks": [], "active": ""])
        let second = Task { await store.run() }; try await reached { pauses.count == 2 }
        pauses[0].resume(); await first.value; XCTAssertTrue(store.isPolling)
        second.cancel(); pauses[1].resume(); await second.value
        XCTAssertFalse(store.isPolling); XCTAssertEqual(durations, [.seconds(10), .seconds(10)]); XCTAssertEqual(api.calls.count, 2)
    }
    @MainActor func testAlreadyCancelledOperationAndReadDoNotSend() async throws {
        let api = ChatTestTransport(); let store = TaskStore(service: TaskService(client: api))
        let mutation = Task { await store.create(draft()) }; mutation.cancel()
        guard case .notStarted = await mutation.value else { return XCTFail("Cancelled mutation began") }
        let read = Task { await store.refreshList() }; read.cancel(); await read.value
        XCTAssertTrue(api.calls.isEmpty); XCTAssertNil(store.list.failure); XCTAssertFalse(store.list.isLoading)
    }
}
