import Foundation
import XCTest
@testable import NetworkPNTRCore

final class ChatUserBodyStoreTests: XCTestCase {
    private let structured = #"{"text":"full text","attachments":[{"name":"a","path":"uploads/a","size":1}]}"#
    private func event(_ seq: Int64 = 1, summary: String = "summary", detail: String? = nil, kind: String = "user") throws -> ChatActivity {
        var value: [String: Any] = ["seq": seq, "worker": "auto", "ts": "fixture", "kind": kind, "summary": summary]
        value["detail"] = detail
        return try BackendJSONCoding.decode(ChatActivity.self, from: JSONSerialization.data(withJSONObject: value))
    }
    @MainActor private func waitFor(_ condition: () -> Bool) async {
        for _ in 0..<3000 { if condition() { return }; await Task.yield() }
        XCTFail("Missing controlled detail request")
    }
    @MainActor func testInlineDetailAvoidsNetworkAndInitialSummaryIsImmediatelyVisible() async throws {
        let model = ChatUserBodyStore(summary: "summary", detail: structured)
        XCTAssertEqual(model.body.text, "full text"); XCTAssertEqual(model.body.attachments.count, 1)
        var calls = 0
        await model.load(conversationID: 7, activity: try event(detail: structured)) { _, _ in calls += 1; return "wrong" }
        XCTAssertEqual(calls, 0); XCTAssertFalse(model.isLoading); XCTAssertNil(model.error)
    }
    @MainActor func testVisibleUserRowRequestsOwnConversationAndSequenceThenParsesFullBody() async throws {
        let model = ChatUserBodyStore(summary: "summary")
        var request: (Int64, Int64)?, reply: CheckedContinuation<String, Error>?
        let item = try event(12)
        let pending = Task { await model.load(conversationID: 7, activity: item) { owner, seq in
            request = (owner, seq); return try await withCheckedThrowingContinuation { reply = $0 }
        } }
        await waitFor { reply != nil }
        XCTAssertEqual(model.body.text, "summary"); XCTAssertTrue(model.isLoading)
        XCTAssertEqual(request?.0, 7); XCTAssertEqual(request?.1, 12)
        reply?.resume(returning: structured); await pending.value
        XCTAssertEqual(model.body.text, "full text"); XCTAssertEqual(model.body.attachments.count, 1)
        XCTAssertFalse(model.isLoading); XCTAssertNil(model.error)
    }
    @MainActor func testEmptyDetailAndFailureRetainSummaryWithSafeRetry() async throws {
        let model = ChatUserBodyStore(summary: "summary"), item = try event()
        await model.load(conversationID: 7, activity: item) { _, _ in "" }
        XCTAssertEqual(model.body.text, "summary"); XCTAssertNil(model.error)
        await model.load(conversationID: 7, activity: item) { _, _ in throw NSError(domain: "/private/fixture/secret", code: 1) }
        XCTAssertEqual(model.body.text, "summary"); XCTAssertNotNil(model.error)
        XCTAssertFalse(model.error?.contains("private") ?? true)
        await model.load(conversationID: 7, activity: item) { _, _ in self.structured }
        XCTAssertEqual(model.body.text, "full text"); XCTAssertNil(model.error)
    }
    @MainActor func testOldReplyAndDeferCannotAffectReplacementOwnerInEitherOrder() async throws {
        for oldFirst in [true, false] {
            let model = ChatUserBodyStore(summary: "old"), oldEvent = try event(summary: "old"), newEvent = try event(summary: "new")
            var oldReply: CheckedContinuation<String, Error>?, newReply: CheckedContinuation<String, Error>?
            let old = Task { await model.load(conversationID: 7, activity: oldEvent) { _, _ in try await withCheckedThrowingContinuation { oldReply = $0 } } }
            await waitFor { oldReply != nil }
            let new = Task { await model.load(conversationID: 8, activity: newEvent) { _, _ in try await withCheckedThrowingContinuation { newReply = $0 } } }
            await waitFor { newReply != nil }
            if oldFirst {
                oldReply?.resume(returning: "obsolete body"); await old.value
                XCTAssertEqual(model.body.text, "new"); XCTAssertTrue(model.isLoading)
                newReply?.resume(returning: structured); await new.value
            } else {
                newReply?.resume(returning: structured); await new.value
                oldReply?.resume(throwing: NSError(domain: "obsolete", code: 1)); await old.value
            }
            XCTAssertEqual(model.body.text, "full text"); XCTAssertNil(model.error); XCTAssertFalse(model.isLoading)
        }
    }
    @MainActor func testStopAndTaskCancellationIgnoreLateResultsWithoutRevivingLoading() async throws {
        for stop in [true, false] {
            let model = ChatUserBodyStore(summary: "summary"), item = try event()
            var reply: CheckedContinuation<String, Error>?
            let pending = Task { await model.load(conversationID: 7, activity: item) { _, _ in try await withCheckedThrowingContinuation { reply = $0 } } }
            await waitFor { reply != nil }
            if stop { model.stop(); XCTAssertFalse(model.isLoading) } else { pending.cancel() }
            reply?.resume(returning: structured); await pending.value
            XCTAssertEqual(model.body.text, "summary"); XCTAssertNil(model.error); XCTAssertFalse(model.isLoading)
        }
    }
    @MainActor func testSameKeyReloadKeepsBodyWhileWaitingAndFailedReloadFallsBackLikeBrowser() async throws {
        let model = ChatUserBodyStore(summary: "summary"), item = try event()
        await model.load(conversationID: 7, activity: item) { _, _ in self.structured }
        model.stop()
        var reply: CheckedContinuation<String, Error>?
        let pending = Task { await model.load(conversationID: 7, activity: item) { _, _ in try await withCheckedThrowingContinuation { reply = $0 } } }
        await waitFor { reply != nil }
        XCTAssertEqual(model.body.text, "full text"); XCTAssertTrue(model.isLoading)
        reply?.resume(throwing: NSError(domain: "fixture", code: 1)); await pending.value
        XCTAssertEqual(model.body.text, "summary"); XCTAssertNotNil(model.error)
    }
    @MainActor func testEmptyInlineFetchesAndNonUserOrInvalidIdentitiesDoNotFetch() async throws {
        let model = ChatUserBodyStore(summary: "summary")
        var calls = 0
        await model.load(conversationID: 7, activity: try event(detail: "")) { _, _ in calls += 1; return "detail" }
        XCTAssertEqual(calls, 1)
        for (owner, item) in [(Int64(0), try event()), (7, try event(0)), (7, try event(kind: "text"))] {
            await model.load(conversationID: owner, activity: item) { _, _ in calls += 1; return "wrong" }
            XCTAssertFalse(model.isLoading)
        }
        XCTAssertEqual(calls, 1)
    }
    func testLoadKeyPreservesExactUnicodeAndDistinguishesOwnerSequenceAndInline() throws {
        let nfc = try event(summary: "\u{E9}"), nfd = try event(summary: "e\u{301}")
        let key = ChatUserBodyKey(conversationID: 7, activity: nfc)
        XCTAssertNotEqual(key, ChatUserBodyKey(conversationID: 7, activity: nfd))
        XCTAssertNotEqual(key, ChatUserBodyKey(conversationID: 8, activity: nfc))
        XCTAssertNotEqual(key, ChatUserBodyKey(conversationID: 7, activity: try event(2, summary: "\u{E9}")))
        XCTAssertNotEqual(key, ChatUserBodyKey(conversationID: 7, activity: try event(summary: "\u{E9}", detail: structured)))
        XCTAssertEqual(key, ChatUserBodyKey(conversationID: 7, activity: try event(summary: "\u{E9}", detail: "")))
    }
}
