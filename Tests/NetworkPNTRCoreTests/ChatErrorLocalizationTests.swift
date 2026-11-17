import XCTest
@testable import NetworkPNTRCore

final class ChatErrorLocalizationTests: XCTestCase {
    @MainActor func testFailedSendResolvesLanguageWithoutChangingOwnerDraftOrCards() async throws {
        let api = ChatTestTransport(); let store = ChatStore(service: ChatService(client: api))
        try api.enqueue(ChatFixture.page([], cursor: 0)); await store.select(id: 7)
        store.draft = "literal 日本語 中文 한국어"
        let card = try JSONDecoder().decode(ChatAttachment.self, from: JSONSerialization.data(withJSONObject: ["name":"fixture.txt","path":"uploads/fixture.txt","size":21,"mime":"text/plain"]))
        try store.appendAttachments([card], for: 7)
        try api.enqueue(["error":"No LLM configuration exists yet: add one under System → LLM settings"], status: 503)
        let sent = await store.sendCurrentDraft(); XCTAssertFalse(sent)
        let count = api.calls.count
        let failure = try XCTUnwrap(store.mutationFailure)
        XCTAssertEqual(failure.text(language: .english), "No LLM configuration exists. Add a provider under System → LLM settings.")
        XCTAssertEqual(failure.text(language: .japanese), store.mutationError)
        XCTAssertEqual(failure.text(language: .english), "No LLM configuration exists. Add a provider under System → LLM settings.")
        XCTAssertEqual(api.calls.count,count); XCTAssertEqual(store.selectedID,7)
        XCTAssertEqual(store.draft,"literal 日本語 中文 한국어"); XCTAssertEqual(store.attachments.map(\.path),[card.path])
    }
    @MainActor func testListHistoryWorkspaceAndUnavailableUploadKeepTypedFailures() async throws {
        let api = ChatTestTransport(); let workspace = ChatWorkspace(client: api)
        try api.enqueue(["error":"private"],status:429); await workspace.transcript.refreshList()
        XCTAssertEqual(workspace.transcript.listFailure?.text(language: .english),"Too many attempts. Wait a while and try again.")
        try api.enqueue(["error":"private"],status:403); await workspace.select(7)
        XCTAssertEqual(workspace.transcript.transcriptFailure?.text(language: .english),"This operation is not allowed. Check the initial setup state.")
        try api.enqueue(["error":"private"],status:409); await workspace.load()
        XCTAssertEqual(workspace.failure?.text(language: .english),"Communication with the runtime failed (HTTP 409).")
        _ = await workspace.pickFiles([URL(fileURLWithPath:"/unused")])
        XCTAssertEqual(workspace.uploadFailure?.text(language: .english),"This connection cannot transfer attachments.")
        XCTAssertEqual(workspace.uploadFailure?.text(language: .japanese),workspace.uploadError)
    }
    @MainActor func testUnknownMentionAndUserBodyFailureHaveSafeLocalizedFallbacks() async throws {
        let api = ChatTestTransport(); api.handler = { _ in throw NSError(domain:"private",code:1,userInfo:[NSLocalizedDescriptionKey:"private-secret"]) }
        let mentions = ChatMentionSearchStore(service: ChatMentionService(client: api))
        await mentions.search(query: "literal")
        XCTAssertEqual(mentions.failure?.text(language: .english),"Could not load reference suggestions. Search again.")
        XCTAssertEqual(mentions.failure?.text(language: .japanese),mentions.error)
        let body = ChatUserBodyStore(summary:"literal 中文 한국어")
        var event = ChatFixture.event(1,summary:"literal 中文 한국어"); event["kind"]="user"
        let activity = try JSONDecoder().decode(ChatActivity.self, from: JSONSerialization.data(withJSONObject:event))
        await body.load(conversationID:7,activity:activity) { _,_ in throw BackendAPIError.status(503) }
        XCTAssertEqual(body.failure?.text(language: .english),"Could not load the message body.")
        XCTAssertEqual(body.failure?.text(language: .japanese),body.error)
        XCTAssertEqual(body.body.text,"literal 中文 한국어")
    }
}
