import XCTest
@testable import ArtexCore

final class ChatWorkspaceTests: XCTestCase {
    @MainActor func testFirstSendCreatesOnceAndKeepsDraftWhenSendFails() async throws {
        let api = ChatTestTransport(); let workspace = ChatWorkspace(client: api)
        workspace.agentKey = "auto"; workspace.transcript.draft = "keep me"
        try api.enqueue(ChatFixture.conversation())
        try api.enqueue(ChatFixture.page([], cursor: 0))
        try api.enqueue(["error": "private"], status: 409)
        try api.enqueue(["conversations": [ChatFixture.conversation()]])
        let result = await workspace.send()
        XCTAssertFalse(result); XCTAssertEqual(workspace.transcript.selectedID, 7)
        XCTAssertEqual(workspace.transcript.draft, "keep me")
        XCTAssertEqual(api.calls.filter { $0.method == "POST" && $0.path == "/api/conversations" }.count, 1)
    }
    @MainActor func testObsoleteCreationDoesNotChangeSelectionOrLoseNewDraft() async throws {
        let api = ChatTestTransport(); let workspace = ChatWorkspace(client: api)
        workspace.agentKey = "auto"; workspace.transcript.draft = "first"
        var pending: CheckedContinuation<BackendHTTPResponse, any Error>?
        api.handler = { _ in try await withCheckedThrowingContinuation { pending = $0 } }
        let creating = Task { await workspace.send() }
        for _ in 0..<2000 { if pending != nil { break }; await Task.yield() }
        XCTAssertNotNil(pending)
        await workspace.select(nil); workspace.transcript.draft = "new draft"
        pending?.resume(returning: try ChatTestTransport.response(ChatFixture.conversation()))
        let result = await creating.value
        XCTAssertFalse(result); XCTAssertNil(workspace.transcript.selectedID)
        XCTAssertEqual(workspace.transcript.draft, "new draft"); XCTAssertEqual(api.calls.count, 1)
    }
    @MainActor func testPartialDeleteClearsOnlyConfirmedSelection() async throws {
        let api = ChatTestTransport(); let workspace = ChatWorkspace(client: api)
        try api.enqueue(ChatFixture.page([], cursor: 0)); await workspace.select(7)
        try api.enqueue(["items": [["id":7,"ok":true],["id":8,"ok":false,"error":"private"]]])
        try api.enqueue(["conversations": [ChatFixture.conversation(8)]])
        let results = await workspace.delete(ids: [7,8])
        XCTAssertEqual(results.filter(\.ok).map(\.id), [7]); XCTAssertNil(workspace.transcript.selectedID)
        XCTAssertNotNil(workspace.error); XCTAssertFalse(workspace.error?.contains("private") ?? true)
    }
    func testSendKeyPolicyPreservesIMEAndBothModes() {
        XCTAssertTrue(ChatSendPolicy.shouldSend(mode: "enter", shift: false, control: false, command: false, composing: false))
        XCTAssertFalse(ChatSendPolicy.shouldSend(mode: "enter", shift: true, control: false, command: false, composing: false))
        for mode in ["enter","ctrl-enter"] {
            XCTAssertFalse(ChatSendPolicy.shouldSend(mode: mode, shift: false, control: true, command: true, composing: true))
        }
        XCTAssertTrue(ChatSendPolicy.shouldSend(mode: "ctrl-enter", shift: false, control: false, command: true, composing: false))
        XCTAssertTrue(ChatSendPolicy.shouldSend(mode: "ctrl-enter", shift: true, control: true, command: false, composing: false))
        XCTAssertFalse(ChatSendPolicy.shouldSend(mode: "ctrl-enter", shift: false, control: false, command: false, composing: false))
    }
}
