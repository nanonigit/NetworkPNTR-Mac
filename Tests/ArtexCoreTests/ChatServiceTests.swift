import XCTest
@testable import ArtexCore

final class ChatServiceTests: XCTestCase {
    @MainActor private func body(_ api: ChatTestTransport) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(api.calls.last?.body)) as? [String: Any])
    }
    @MainActor func testCreateAndMutationsUseExactKeysAndExplicitDefaultProfileNull() async throws {
        let api = ChatTestTransport(); let service = ChatService(client: api)
        try api.enqueue(["conversations": [ChatFixture.conversation()]])
        let list = try await service.conversations(); XCTAssertEqual(list.first?.id, 7)
        try api.enqueue(ChatFixture.conversation())
        let saved = try await service.create(agentKey: "auto")
        XCTAssertEqual(saved.id, 7)
        XCTAssertEqual(api.calls.last?.path, "/api/conversations")
        XCTAssertTrue(try body(api)["llm_profile_id"] is NSNull)
        try api.enqueue(ChatFixture.conversation(title: "renamed"))
        _ = try await service.rename(id: 7, title: "renamed")
        XCTAssertEqual(Set(try body(api).keys), ["title"])
        try api.enqueue(ChatFixture.conversation().merging(["pinned": true]) { _, b in b })
        _ = try await service.pin(id: 7, pinned: true)
        XCTAssertEqual(Set(try body(api).keys), ["pinned"])
        XCTAssertEqual(api.calls.last?.method, "PATCH")
        try api.enqueue(["ok": true]); try await service.setProfile(id: 7, profileID: nil)
        XCTAssertEqual(api.calls.last?.path, "/api/conversations/7/profile")
        XCTAssertTrue(try body(api)["llm_profile_id"] is NSNull)
        try api.enqueue(["ok": true]); try await service.setProfile(id: 7, profileID: 9)
        XCTAssertEqual(try body(api)["llm_profile_id"] as? Int, 9)
    }
    @MainActor func testHistoryAndTailQueriesKeepPaginationAndNormalizeNullableEmptyItems() async throws {
        let api = ChatTestTransport(); let service = ChatService(client: api)
        try api.enqueue(ChatFixture.page([1, 2], cursor: 2, running: true, hasMore: true))
        let first = try await service.history(id: 7)
        XCTAssertEqual(api.calls.last?.path, "/api/conversations/7/messages?limit=200")
        XCTAssertEqual(first.items.map(\.seq), [1, 2]); XCTAssertTrue(first.hasMore)
        try api.enqueue(ChatFixture.page([1], cursor: 1))
        _ = try await service.history(id: 7, before: 2)
        XCTAssertEqual(api.calls.last?.path, "/api/conversations/7/messages?limit=200&before=2")
        try api.enqueue(["items": NSNull(), "cursor": 2, "running": false])
        let delta = try await service.delta(id: 7, since: 2)
        XCTAssertTrue(delta.items.isEmpty); XCTAssertFalse(delta.running)
        XCTAssertEqual(api.calls.last?.path, "/api/conversations/7/messages?since=2")
        try api.enqueue(["detail": "full guest output"])
        let detail = try await service.detail(id: 7, sequence: 2)
        XCTAssertEqual(detail, "full guest output")
        XCTAssertEqual(api.calls.last?.path, "/api/conversations/7/messages/2")
    }
    @MainActor func testAcceptedSendAndStopDoNotPretendAgentHasAlreadyFinished() async throws {
        let api = ChatTestTransport(); let service = ChatService(client: api)
        try api.enqueue(["status": "accepted"], status: 202)
        try await service.send(id: 7, message: "  draft\nline  ")
        XCTAssertEqual(try body(api)["message"] as? String, "  draft\nline  ")
        XCTAssertEqual(api.calls.last?.path, "/api/conversations/7/messages")
        try api.enqueue(["status": "stopping"])
        let stopping = try await service.stop(id: 7); XCTAssertEqual(stopping, .stopping)
        try api.enqueue(["status": "idle"])
        let idle = try await service.stop(id: 7); XCTAssertEqual(idle, .idle)
        XCTAssertEqual(api.calls.last?.path, "/api/conversations/7/stop")
        try api.enqueue(["status": "finished"])
        do { _ = try await service.stop(id: 7); XCTFail("Unknown stop acknowledgement") } catch {}
    }
    @MainActor func testBatchPartialFailureAndSingleDeleteAcknowledgementsAreValidated() async throws {
        let api = ChatTestTransport(); let service = ChatService(client: api)
        try api.enqueue(["items": [["id": 7, "ok": true], ["id": 8, "ok": false, "error": "private-backend-error"]]])
        let result = try await service.deleteBatch(ids: [7, 8, 7])
        XCTAssertEqual(result.map(\.id), [7, 8]); XCTAssertEqual(result.map(\.ok), [true, false])
        XCTAssertEqual(try body(api)["ids"] as? [Int], [7, 8])
        XCTAssertFalse(String(describing: result).contains("private-backend-error"))
        try api.enqueue(["deleted": 7]); try await service.delete(id: 7)
        XCTAssertEqual(api.calls.last?.method, "DELETE")
        try api.enqueue(["deleted": 8])
        do { try await service.delete(id: 7); XCTFail("Wrong deleted ID") } catch {}
        for items in [[["id": 7, "ok": true]], [["id": 7, "ok": true], ["id": 7, "ok": true]]] {
            try api.enqueue(["items": items])
            do { _ = try await service.deleteBatch(ids: [7, 8]); XCTFail("Incomplete/duplicate response") } catch {}
        }
    }
    @MainActor func testInvalidInputsNeverReachTransportAndUnicodeLimitsCountScalars() async throws {
        let api = ChatTestTransport(); let service = ChatService(client: api)
        do { _ = try await service.history(id: 0); XCTFail() } catch {}
        do { _ = try await service.history(id: 7, before: -1); XCTFail() } catch {}
        do { _ = try await service.delta(id: 7, since: -1); XCTFail() } catch {}
        do { _ = try await service.detail(id: 7, sequence: 0); XCTFail() } catch {}
        do { _ = try await service.create(agentKey: "  "); XCTFail() } catch {}
        do { _ = try await service.create(agentKey: String(repeating: "か\u{3099}", count: 61)); XCTFail() } catch {}
        do { _ = try await service.rename(id: 7, title: "\n"); XCTFail() } catch {}
        do { _ = try await service.rename(id: 7, title: String(repeating: "か\u{3099}", count: 101)); XCTFail() } catch {}
        do { try await service.setProfile(id: 7, profileID: 0); XCTFail() } catch {}
        do { _ = try await service.deleteBatch(ids: []); XCTFail() } catch {}
        do { _ = try await service.deleteBatch(ids: Array(1...101).map(Int64.init)); XCTFail() } catch {}
        do { try await service.send(id: 7, message: " \n"); XCTFail() } catch {}
        XCTAssertTrue(api.calls.isEmpty)
    }
    @MainActor func testMalformedAndErrorResponsesCannotBecomeEmptySuccessOrLeakBodies() async throws {
        let api = ChatTestTransport(); let service = ChatService(client: api)
        for status in [401, 403, 409, 500, 503] {
            try api.enqueue(["error": "private-backend-error"], status: status)
            do { _ = try await service.conversations(); XCTFail() }
            catch { XCTAssertFalse(error.localizedDescription.contains("private-backend-error")) }
        }
        for object in [["unexpected": true], ["conversations": "wrong"], ["conversations": [ChatFixture.conversation(0)]]] as [[String: Any]] {
            try api.enqueue(object)
            do { _ = try await service.conversations(); XCTFail("Malformed collection") } catch {}
        }
        try api.enqueue(["items": "wrong", "cursor": 0, "running": false])
        do { _ = try await service.history(id: 7); XCTFail() } catch {}
        try api.enqueue(["ok": false])
        do { try await service.setProfile(id: 7, profileID: nil); XCTFail() } catch {}
        try api.enqueue(["status": "not-accepted"])
        do { try await service.send(id: 7, message: "draft"); XCTFail() } catch {}
    }
}
