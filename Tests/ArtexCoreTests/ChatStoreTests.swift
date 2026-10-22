import XCTest
@testable import ArtexCore

final class ChatStoreTests: XCTestCase {
    @MainActor private func waitFor(_ condition: () -> Bool) async {
        for _ in 0..<2000 {
            if condition() { return }
            await Task.yield()
        }
        XCTFail("Controlled request did not reach its suspension point")
    }
    @MainActor func testListRequestDoesNotOverlapAndFailurePreservesExistingList() async throws {
        let api = ChatTestTransport(); let store = ChatStore(service: ChatService(client: api))
        var pending: CheckedContinuation<BackendHTTPResponse, any Error>?
        api.handler = { _ in try await withCheckedThrowingContinuation { pending = $0 } }
        let first = Task { await store.refreshList() }
        await waitFor { pending != nil }
        await store.refreshList(); XCTAssertEqual(api.calls.count, 1)
        pending?.resume(returning: try ChatTestTransport.response(["conversations": [ChatFixture.conversation()]]))
        await first.value
        api.handler = nil; try api.enqueue(["error": "private-error"], status: 503)
        await store.refreshList()
        XCTAssertEqual(store.conversations.map(\.id), [7]); XCTAssertNotNil(store.listError)
        XCTAssertFalse(store.listError?.contains("private-error") ?? true)
    }
    @MainActor func testLateHistoryCannotOverwriteNewSelectionOrItsLoadingFlag() async throws {
        let api = ChatTestTransport(); let store = ChatStore(service: ChatService(client: api))
        var pending: [String: CheckedContinuation<BackendHTTPResponse, any Error>] = [:]
        api.handler = { call in try await withCheckedThrowingContinuation { pending[call.path] = $0 } }
        let old = Task { await store.select(id: 7) }
        await waitFor { pending.count == 1 }
        let current = Task { await store.select(id: 8) }
        await waitFor { pending.count == 2 }
        pending["/api/conversations/7/messages?limit=200"]?.resume(returning: try ChatTestTransport.response(ChatFixture.page([70], cursor: 70)))
        await old.value
        XCTAssertEqual(store.selectedID, 8); XCTAssertTrue(store.isLoadingHistory); XCTAssertTrue(store.messages.isEmpty)
        pending["/api/conversations/8/messages?limit=200"]?.resume(returning: try ChatTestTransport.response(ChatFixture.page([80], cursor: 80, running: true)))
        await current.value
        XCTAssertEqual(store.messages.map(\.seq), [80]); XCTAssertTrue(store.running); XCTAssertFalse(store.isLoadingHistory)
    }
    @MainActor func testOlderHistoryMergesWithConcurrentTailWithoutRegressingCursor() async throws {
        let api = ChatTestTransport(); let store = ChatStore(service: ChatService(client: api))
        try api.enqueue(ChatFixture.page([201, 202], cursor: 202, running: true, hasMore: true))
        await store.select(id: 7)
        var older: CheckedContinuation<BackendHTTPResponse, any Error>?
        api.handler = { call in
            if call.path.contains("before=") { return try await withCheckedThrowingContinuation { older = $0 } }
            return try ChatTestTransport.response(ChatFixture.page([203], cursor: 203))
        }
        let loading = Task { await store.loadOlder() }
        await waitFor { older != nil }
        await store.refreshDelta()
        var page = ChatFixture.page([1, 201], cursor: 201)
        page["items"] = [ChatFixture.event(1), ChatFixture.event(201, summary: "stale old page")]
        older?.resume(returning: try ChatTestTransport.response(page)); await loading.value
        XCTAssertEqual(store.messages.map(\.seq), [1, 201, 202, 203]); XCTAssertEqual(store.cursor, 203)
        XCTAssertEqual(store.messages[1].summary, "fixture"); XCTAssertFalse(store.hasMore)
        XCTAssertEqual(store.messages.last?.seq, 203); XCTAssertFalse(store.running)
    }
    @MainActor func testConfirmedSendPreservesNewerDraftAndDoesNotFailBecauseRefreshFailed() async throws {
        let api = ChatTestTransport(); let store = ChatStore(service: ChatService(client: api))
        try api.enqueue(ChatFixture.page([], cursor: 0)); await store.select(id: 7)
        store.draft = "submitted"
        var accepted: CheckedContinuation<BackendHTTPResponse, any Error>?
        api.handler = { call in
            if call.method == "POST" { return try await withCheckedThrowingContinuation { accepted = $0 } }
            return try ChatTestTransport.response(["error": "private-error"], status: 503)
        }
        let sending = Task { await store.sendCurrentDraft() }
        await waitFor { accepted != nil }
        store.draft = "newer draft"
        let duplicate = await store.sendCurrentDraft(); XCTAssertFalse(duplicate)
        accepted?.resume(returning: try ChatTestTransport.response(["status": "accepted"], status: 202))
        let success = await sending.value
        XCTAssertTrue(success); XCTAssertEqual(store.draft, "newer draft"); XCTAssertTrue(store.running)
        XCTAssertNotNil(store.transcriptError); XCTAssertNil(store.mutationError)
    }
    @MainActor func testSendFailureKeepsDraftAndResetRejectsLateAcceptedCallback() async throws {
        let api = ChatTestTransport(); let store = ChatStore(service: ChatService(client: api))
        try api.enqueue(ChatFixture.page([], cursor: 0)); await store.select(id: 7); store.draft = "retain me"
        try api.enqueue(["error": "private-error"], status: 409)
        let failed = await store.sendCurrentDraft(); XCTAssertFalse(failed); XCTAssertEqual(store.draft, "retain me")
        XCTAssertNotNil(store.mutationError)
        var accepted: CheckedContinuation<BackendHTTPResponse, any Error>?
        api.handler = { _ in try await withCheckedThrowingContinuation { accepted = $0 } }
        let sending = Task { await store.sendCurrentDraft() }; await waitFor { accepted != nil }
        store.reset()
        accepted?.resume(returning: try ChatTestTransport.response(["status": "accepted"], status: 202))
        let result = await sending.value
        XCTAssertFalse(result); XCTAssertNil(store.selectedID); XCTAssertTrue(store.messages.isEmpty)
        XCTAssertTrue(store.conversations.isEmpty); XCTAssertEqual(store.draft, ""); XCTAssertFalse(store.isSending)
    }
    @MainActor func testStoppedTailDrainsFullBurstAndCursorNeverRegresses() async throws {
        let api = ChatTestTransport(); let store = ChatStore(service: ChatService(client: api))
        try api.enqueue(ChatFixture.page([1], cursor: 1, running: true)); await store.select(id: 7)
        try api.enqueue(ChatFixture.page(Array(2...1001).map(Int64.init), cursor: 0))
        await store.refreshDelta()
        XCTAssertFalse(store.running); XCTAssertTrue(store.needsTailReconciliation); XCTAssertEqual(store.cursor, 1001)
        try api.enqueue(ChatFixture.page([1002], cursor: 2)); await store.refreshDelta()
        XCTAssertEqual(store.cursor, 1002); XCTAssertEqual(store.messages.count, 1002)
        XCTAssertFalse(store.needsTailReconciliation)
        let count = api.calls.count; await store.refreshDelta(); XCTAssertEqual(api.calls.count, count)
    }
    @MainActor func testPollingAwaitsRequestsAndStopsAfterGenerationInvalidation() async throws {
        let api = ChatTestTransport()
        var waits: [Duration] = []; var sleepers: [CheckedContinuation<Void, any Error>] = []
        let store = ChatStore(service: ChatService(client: api), sleep: { duration in
            waits.append(duration); try await withCheckedThrowingContinuation { sleepers.append($0) }
        })
        try api.enqueue(["conversations": []])
        let poll = Task { await store.pollList() }
        await waitFor { sleepers.count == 1 }
        XCTAssertEqual(waits, [.seconds(2)]); XCTAssertEqual(api.calls.count, 1)
        await store.pollList(); XCTAssertEqual(api.calls.count, 1)
        store.stop(); sleepers.removeFirst().resume(); await poll.value
        XCTAssertFalse(store.isLoadingList)
        try api.enqueue(ChatFixture.page([], cursor: 0, running: true)); await store.select(id: 7)
        try api.enqueue(ChatFixture.page([1], cursor: 1))
        let tail = Task { await store.pollSelected() }
        await waitFor { sleepers.count == 1 }
        XCTAssertEqual(waits.last, .seconds(1)); XCTAssertEqual(store.messages.map(\.seq), [1])
        store.stop(); sleepers.removeFirst().resume(); await tail.value
    }
    @MainActor func testResumeReconcilesFinalMessagesAfterPollingWasStopped() async throws {
        let api = ChatTestTransport(); let store = ChatStore(service: ChatService(client: api))
        try api.enqueue(ChatFixture.page([1], cursor: 1, running: true)); await store.select(id: 7)
        store.stop()
        try api.enqueue(["conversations": [ChatFixture.conversation(running: false)]])
        await store.refreshList()
        try api.enqueue(ChatFixture.page([2], cursor: 2, running: false)); await store.refreshDelta()
        XCTAssertEqual(store.messages.map(\.seq), [1, 2])
        XCTAssertEqual(store.cursor, 2); XCTAssertFalse(store.running)
    }
    @MainActor func testStopAcknowledgementStillReadsFinalTailAndUnchangedSubmittedDraftClears() async throws {
        let api = ChatTestTransport(); let store = ChatStore(service: ChatService(client: api))
        try api.enqueue(ChatFixture.page([], cursor: 0)); await store.select(id: 7); store.draft = "send"
        try api.enqueue(["status": "accepted"], status: 202)
        try api.enqueue(["conversations": [ChatFixture.conversation(running: true)]])
        try api.enqueue(ChatFixture.page([1], cursor: 1, running: true))
        let sent = await store.sendCurrentDraft()
        XCTAssertTrue(sent); XCTAssertEqual(store.draft, ""); XCTAssertTrue(store.running)
        try api.enqueue(["status": "stopping"])
        try api.enqueue(ChatFixture.page([2], cursor: 2))
        let stopped = await store.requestStop()
        XCTAssertTrue(stopped); XCTAssertFalse(store.running); XCTAssertFalse(store.isStopping)
        XCTAssertEqual(store.messages.map(\.seq), [1, 2])
        try api.enqueue(["error": "private-error"], status: 503)
        let failed = await store.requestStop(); XCTAssertFalse(failed)
        XCTAssertFalse(store.mutationError?.contains("private-error") ?? true)
    }

}
