import Foundation
import XCTest
@testable import ArtexCore

final class ChatAttachmentStoreTests: XCTestCase {
    private func attachment(_ name: String) throws -> ChatAttachment {
        try ChatAttachment(name: name, path: "uploads/" + name, size: 1)
    }
    @MainActor private func store(_ api: ChatTestTransport) async throws -> ChatStore {
        let store = ChatStore(service: ChatService(client: api))
        try api.enqueue(ChatFixture.page([], cursor: 0)); await store.select(id: 7)
        return store
    }
    @MainActor private func waitFor(_ condition: () -> Bool) async {
        for _ in 0..<2000 { if condition() { return }; await Task.yield() }
        XCTFail("Missing controlled send")
    }
    @MainActor func testCardsAreKeyedByConversationAndRemovalNeverDeletesGuestFile() async throws {
        let api = ChatTestTransport(), store = try await store(api), first = try attachment("a"), second = try attachment("b")
        try store.appendAttachments([first,second], for: 7)
        XCTAssertEqual(store.attachments, [first,second])
        XCTAssertThrowsError(try store.appendAttachments([first], for: 7))
        XCTAssertThrowsError(try store.appendAttachments([first], for: 0))
        let calls = api.calls.count
        store.removeAttachment(path: first.path, for: 7)
        XCTAssertEqual(store.attachments, [second]); XCTAssertEqual(api.calls.count, calls)
        try api.enqueue(ChatFixture.page([], cursor: 0)); await store.select(id: 8)
        XCTAssertTrue(store.attachments.isEmpty)
        try store.appendAttachments([first], for: 8)
        XCTAssertEqual(store.attachments(for: 7), [second])
        XCTAssertEqual(store.attachments(for: 8), [first])
    }
    @MainActor func testCanonicalEquivalentPathsAppendRestoreAndRemoveOnlyExactGuestFile() async throws {
        let api = ChatTestTransport(), store = try await store(api)
        let first = try attachment("\u{E9}.txt"), second = try attachment("e\u{301}.txt")
        try store.appendAttachments([first,second], for: 7)
        var reply: CheckedContinuation<BackendHTTPResponse, Error>?
        api.handler = { _ in try await withCheckedThrowingContinuation { reply = $0 } }
        let pending = Task { await store.sendCurrentDraft() }; await waitFor { reply != nil }
        try store.appendAttachments([second], for: 7)
        reply?.resume(returning: try ChatTestTransport.response(["error":"private"],status:503))
        let accepted = await pending.value; XCTAssertFalse(accepted)
        XCTAssertEqual(store.attachments.count, 2)
        store.removeAttachment(path: first.path, for: 7)
        XCTAssertEqual(store.attachments.count, 1)
        XCTAssertTrue(store.attachments[0].path.utf8.elementsEqual(second.path.utf8))
    }
    @MainActor func testOptimisticClearRestoresBodyAndCardsOnFailure() async throws {
        let api = ChatTestTransport(), store = try await store(api), file = try attachment("a")
        store.draft = "retry me"; try store.appendAttachments([file], for: 7)
        var reply: CheckedContinuation<BackendHTTPResponse, Error>?
        api.handler = { _ in try await withCheckedThrowingContinuation { reply = $0 } }
        let pending = Task { await store.sendCurrentDraft() }
        await waitFor { reply != nil }
        XCTAssertEqual(store.draft, ""); XCTAssertTrue(store.attachments.isEmpty)
        let duplicate = await store.sendCurrentDraft(); XCTAssertFalse(duplicate)
        reply?.resume(returning: try ChatTestTransport.response(["error":"private"], status: 503))
        let accepted = await pending.value; XCTAssertFalse(accepted)
        XCTAssertEqual(store.draft, "retry me"); XCTAssertEqual(store.attachments, [file])
        XCTAssertNotNil(store.mutationError)
    }
    @MainActor func testNewEditsAndCardsSurviveFailureAndSelectionChange() async throws {
        let api = ChatTestTransport(), store = try await store(api), first = try attachment("a"), later = try attachment("b")
        store.draft = "old"; try store.appendAttachments([first], for: 7)
        var reply: CheckedContinuation<BackendHTTPResponse, Error>?
        api.handler = { call in
            if call.method == "POST" { return try await withCheckedThrowingContinuation { reply = $0 } }
            return try ChatTestTransport.response(ChatFixture.page([], cursor: 0))
        }
        let pending = Task { await store.sendCurrentDraft() }; await waitFor { reply != nil }
        store.draft = "new"; try store.appendAttachments([later], for: 7)
        await store.select(id: 8); store.draft = "other conversation"
        reply?.resume(returning: try ChatTestTransport.response(["error":"private"],status:409))
        let accepted = await pending.value; XCTAssertFalse(accepted)
        XCTAssertEqual(store.draft, "other conversation"); XCTAssertTrue(store.attachments.isEmpty)
        XCTAssertEqual(store.draft(for: 7), "new"); XCTAssertEqual(store.attachments(for: 7), [first,later])
    }
    @MainActor func testAttachmentOnlySuccessKeepsNewDraftAndNewCards() async throws {
        let api = ChatTestTransport(), store = try await store(api), first = try attachment("a"), later = try attachment("b")
        try store.appendAttachments([first], for: 7)
        var reply: CheckedContinuation<BackendHTTPResponse, Error>?
        api.handler = { call in
            if call.method == "POST" { return try await withCheckedThrowingContinuation { reply = $0 } }
            if call.path == "/api/conversations" { return try ChatTestTransport.response(["conversations":[ChatFixture.conversation()]]) }
            return try ChatTestTransport.response(ChatFixture.page([],cursor:0))
        }
        let pending = Task { await store.sendCurrentDraft() }; await waitFor { reply != nil }
        store.draft = "next"; try store.appendAttachments([later], for: 7)
        reply?.resume(returning: try ChatTestTransport.response(["status":"accepted"],status:202))
        let accepted = await pending.value; XCTAssertTrue(accepted)
        XCTAssertEqual(store.draft, "next"); XCTAssertEqual(store.attachments, [later])
        let body = try JSONSerialization.jsonObject(with: XCTUnwrap(api.calls.first { $0.method == "POST" }?.body)) as! [String:Any]
        XCTAssertEqual(body["message"] as? String, "")
        XCTAssertEqual((body["attachments"] as? [[String:Any]])?.first?["name"] as? String, "a")
    }
    @MainActor func testStopRestoresUnconfirmedSendButResetAndLateReplyCannotReviveIt() async throws {
        for reset in [false,true] {
            let api = ChatTestTransport(), store = try await store(api), file = try attachment("a")
            store.draft = "restore"; try store.appendAttachments([file], for: 7)
            var reply: CheckedContinuation<BackendHTTPResponse, Error>?
            api.handler = { _ in try await withCheckedThrowingContinuation { reply = $0 } }
            let pending = Task { await store.sendCurrentDraft() }; await waitFor { reply != nil }
            if reset { store.reset() } else { store.stop() }
            reply?.resume(returning: try ChatTestTransport.response(["status":"accepted"],status:202))
            let accepted = await pending.value; XCTAssertFalse(accepted)
            XCTAssertEqual(store.draft(for: 7), reset ? "" : "restore")
            XCTAssertEqual(store.attachments(for: 7), reset ? [] : [file])
        }
    }
    @MainActor func testEditedThenClearedDraftDoesNotGetOldMessageRestored() async throws {
        let api = ChatTestTransport(), store = try await store(api)
        store.draft = "old"
        var reply: CheckedContinuation<BackendHTTPResponse, Error>?
        api.handler = { _ in try await withCheckedThrowingContinuation { reply = $0 } }
        let pending = Task { await store.sendCurrentDraft() }; await waitFor { reply != nil }
        store.draft = "new"; store.draft = ""
        reply?.resume(returning: try ChatTestTransport.response(["error":"private"],status:503))
        let accepted = await pending.value; XCTAssertFalse(accepted); XCTAssertEqual(store.draft, "")
    }
}
