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
    @MainActor func testCreatedConversationRetainsDraftWhenSelectionChangesDuringHistoryLoad() async throws {
        let api = ChatTestTransport(); let workspace = ChatWorkspace(client: api)
        workspace.agentKey = "auto"; workspace.transcript.draft = "retain after create"
        var pending: CheckedContinuation<BackendHTTPResponse, any Error>?
        api.handler = { call in
            if call.method == "POST" { return try ChatTestTransport.response(ChatFixture.conversation()) }
            return try await withCheckedThrowingContinuation { pending = $0 }
        }
        let creating = Task { await workspace.send() }
        for _ in 0..<2000 { if pending != nil { break }; await Task.yield() }
        XCTAssertNotNil(pending)
        await workspace.select(nil)
        pending?.resume(returning: try ChatTestTransport.response(ChatFixture.page([], cursor: 0)))
        let result = await creating.value; XCTAssertFalse(result)
        api.handler = nil; try api.enqueue(ChatFixture.page([], cursor: 0))
        await workspace.select(7)
        XCTAssertEqual(workspace.transcript.draft, "retain after create")
    }
    @MainActor func testEditsDuringCreatedHistoryLoadSurviveAndOnlyOriginalMessageIsSubmitted() async throws {
        let api = ChatTestTransport(); let workspace = ChatWorkspace(client: api)
        workspace.agentKey = "auto"; workspace.transcript.draft = "submitted"
        var pending: CheckedContinuation<BackendHTTPResponse, any Error>?
        api.handler = { call in
            if call.path == "/api/conversations", call.method == "POST" { return try ChatTestTransport.response(ChatFixture.conversation()) }
            if call.method == "POST" { return try ChatTestTransport.response(["error":"private"], status: 409) }
            if call.path == "/api/conversations" { return try ChatTestTransport.response(["conversations":[ChatFixture.conversation()]]) }
            return try await withCheckedThrowingContinuation { pending = $0 }
        }
        let sending = Task { await workspace.send() }
        for _ in 0..<2000 { if pending != nil { break }; await Task.yield() }
        workspace.transcript.draft = "newer edit"
        pending?.resume(returning: try ChatTestTransport.response(ChatFixture.page([], cursor: 0)))
        let result = await sending.value; XCTAssertFalse(result)
        XCTAssertEqual(workspace.transcript.draft, "newer edit")
        let sent = try XCTUnwrap(api.calls.first { $0.path.hasSuffix("/messages") && $0.method == "POST" }?.body)
        XCTAssertEqual((try JSONSerialization.jsonObject(with: sent) as? [String:String])?["message"], "submitted")
    }
    @MainActor func testCatalogFiltersBuiltinsDefaultsToAutoAndPreservesOnFailure() async throws {
        let api = ChatTestTransport(); let workspace = ChatWorkspace(client: api)
        func agent(_ key: String, builtin: Bool, role: String) -> [String:Any] {
            ["key":key,"name":key.uppercased(),"description":"fixture","builtin":builtin,"role":role]
        }
        try api.enqueue(["agents":[agent("auto", builtin:true, role:"assistant"), agent("planner", builtin:true, role:"planner"), agent("custom", builtin:false, role:"planner")]])
        try api.enqueue(["profiles":[]]); await workspace.load()
        XCTAssertEqual(workspace.agents.map(\.key), ["auto","custom"]); XCTAssertEqual(workspace.agentKey,"auto")
        XCTAssertEqual(workspace.name(for:"auto"),"AUTO"); XCTAssertEqual(workspace.name(for:"missing"),"missing")
        try api.enqueue(["error":"private"],status:503); await workspace.load()
        XCTAssertEqual(workspace.agents.count,2); XCTAssertNotNil(workspace.error)
        XCTAssertFalse(workspace.error?.contains("private") ?? true); XCTAssertFalse(workspace.loading)
        workspace.stop(); XCTAssertFalse(workspace.busy)
    }
    @MainActor func testConfirmedMutationsRefreshSelectionAndDeleteFailurePreservesIt() async throws {
        let api = ChatTestTransport(); let workspace = ChatWorkspace(client: api)
        try api.enqueue(ChatFixture.page([],cursor:0)); await workspace.select(7)
        var renamed = ChatFixture.conversation(title:"renamed")
        try api.enqueue(renamed); try api.enqueue(["conversations":[renamed]])
        await workspace.rename(id:7,title:"renamed"); XCTAssertEqual(workspace.selected?.title,"renamed")
        renamed["pinned"] = true
        try api.enqueue(renamed); try api.enqueue(["conversations":[renamed]])
        await workspace.pin(id:7,pinned:true); XCTAssertTrue(workspace.selected?.isPinned ?? false)
        try api.enqueue(["ok":true]); try api.enqueue(["conversations":[renamed]])
        await workspace.changeProfile(id:7,profileID:nil); XCTAssertNil(workspace.error)
        try api.enqueue(["detail":"fixture detail"])
        let detail = try await workspace.detail(id:7,sequence:1); XCTAssertEqual(detail,"fixture detail")
        try api.enqueue(["error":"private"],status:503)
        let deleted = await workspace.delete(ids:[7]); XCTAssertTrue(deleted.isEmpty)
        XCTAssertEqual(workspace.transcript.selectedID,7); XCTAssertNotNil(workspace.error)
        XCTAssertFalse(workspace.busy)
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
