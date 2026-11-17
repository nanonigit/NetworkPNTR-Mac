import Foundation
import XCTest
@testable import NetworkPNTRCore

@MainActor final class WorkspaceUploadAPI: BackendJSONTransport, ChatAttachmentUploading {
    struct Upload { let id: Int64; let files: [URL]; let progress: BackendUploadProgressHandler? }
    var calls: [ChatTestTransport.Call] = []
    var uploads: [Upload] = []
    var handler: ((ChatTestTransport.Call) async throws -> BackendHTTPResponse)?
    var uploadHandler: ((Upload) async throws -> [ChatAttachment])?
    var nextID: Int64 = 17
    func send(method: String, path: String, body: Data?, bearer: String?) async throws -> BackendHTTPResponse {
        let call = ChatTestTransport.Call(method:method,path:path,body:body); calls.append(call)
        if let handler { return try await handler(call) }
        if method == "POST", path == "/api/conversations" { return try ChatTestTransport.response(ChatFixture.conversation(nextID)) }
        if path == "/api/conversations/delete/batch" {
            return try ChatTestTransport.response(["items":[["id":7,"ok":true],["id":8,"ok":false]]])
        }
        if path == "/api/conversations" { return try ChatTestTransport.response(["conversations":[ChatFixture.conversation(17),ChatFixture.conversation(7),ChatFixture.conversation(8)]]) }
        return try ChatTestTransport.response(ChatFixture.page([],cursor:0))
    }
    func uploadAttachments(conversationID: Int64, files: [URL], progress: BackendUploadProgressHandler?) async throws -> [ChatAttachment] {
        let upload = Upload(id:conversationID,files:files,progress:progress); uploads.append(upload)
        if let uploadHandler { return try await uploadHandler(upload) }
        return try files.map { try ChatAttachment(name:$0.lastPathComponent,path:"uploads/" + $0.lastPathComponent,size:1) }
    }
}
final class ChatWorkspaceUploadTests: XCTestCase {
    private let files = [URL(fileURLWithPath:"/synthetic/selected.txt")]
    private func attachment(_ name: String = "selected.txt") throws -> ChatAttachment { try ChatAttachment(name:name,path:"uploads/"+name,size:1) }
    @MainActor private func waitFor(_ condition: () -> Bool) async {
        for _ in 0..<3000 { if condition() { return }; await Task.yield() }
        XCTFail("Missing controlled upload state")
    }
    @MainActor func testNewDraftCreatesOnceAndHandsOffTextWithoutSendingAnAgentTurn() async throws {
        let api = WorkspaceUploadAPI(), workspace = ChatWorkspace(client:api)
        workspace.agentKey = "auto"; workspace.transcript.draft = "carry text"
        let accepted = await workspace.pickFiles(files)
        XCTAssertTrue(accepted)
        XCTAssertEqual(workspace.transcript.selectedID,17)
        XCTAssertEqual(workspace.transcript.draft,"carry text")
        XCTAssertEqual(workspace.transcript.draft(for:nil),"")
        XCTAssertEqual(workspace.transcript.attachments,[try attachment()])
        XCTAssertEqual(api.uploads.map(\.id),[17])
        XCTAssertEqual(api.calls.filter { $0.method == "POST" && $0.path == "/api/conversations" }.count,1)
        XCTAssertFalse(api.calls.contains { $0.method == "POST" && $0.path.hasSuffix("/messages") })
        XCTAssertFalse(workspace.isUploading)
    }
    @MainActor func testUnsupportedEmptyAndNoAgentSelectionCannotCreateConversation() async {
        let unsupported = ChatTestTransport(), workspace = ChatWorkspace(client:unsupported)
        workspace.agentKey = "auto"
        let missing = await workspace.pickFiles(files); XCTAssertFalse(missing)
        XCTAssertTrue(unsupported.calls.isEmpty)
        let api = WorkspaceUploadAPI(), empty = ChatWorkspace(client:api)
        let noAgent = await empty.pickFiles(files); XCTAssertFalse(noAgent)
        empty.agentKey = "auto"
        let noFiles = await empty.pickFiles([]); XCTAssertFalse(noFiles)
        XCTAssertTrue(api.calls.isEmpty); XCTAssertTrue(api.uploads.isEmpty)
    }
    @MainActor func testPendingNewUploadIsSingleFlightAndKeepsLatestRootEdit() async throws {
        let api = WorkspaceUploadAPI(), workspace = ChatWorkspace(client:api)
        workspace.agentKey = "auto"; workspace.transcript.draft = "first"
        var reply: CheckedContinuation<[ChatAttachment], Error>?
        api.uploadHandler = { _ in try await withCheckedThrowingContinuation { reply = $0 } }
        let pending = Task { await workspace.pickFiles(self.files) }; await waitFor { reply != nil }
        XCTAssertTrue(workspace.isUploading)
        let duplicate = await workspace.pickFiles(files); XCTAssertFalse(duplicate)
        let send = await workspace.send(); XCTAssertFalse(send)
        workspace.transcript.draft = "latest"
        reply?.resume(returning:[try attachment()])
        let accepted = await pending.value; XCTAssertTrue(accepted)
        XCTAssertEqual(api.uploads.count,1); XCTAssertEqual(workspace.transcript.draft,"latest")
        XCTAssertEqual(workspace.transcript.selectedID,17)
    }
    @MainActor func testExistingUploadStaysWithOriginAndCannotStealSelection() async throws {
        let api = WorkspaceUploadAPI(), workspace = ChatWorkspace(client:api)
        await workspace.select(7)
        var reply: CheckedContinuation<[ChatAttachment], Error>?
        api.uploadHandler = { _ in try await withCheckedThrowingContinuation { reply = $0 } }
        let pending = Task { await workspace.pickFiles(self.files) }; await waitFor { reply != nil }
        await workspace.select(8); workspace.transcript.draft = "other"
        reply?.resume(returning:[try attachment()])
        let accepted = await pending.value; XCTAssertTrue(accepted)
        XCTAssertEqual(workspace.transcript.selectedID,8); XCTAssertEqual(workspace.transcript.draft,"other")
        XCTAssertTrue(workspace.transcript.attachments.isEmpty)
        XCTAssertEqual(workspace.transcript.attachments(for:7),[try attachment()])
        XCTAssertFalse(api.calls.contains { $0.method == "POST" && $0.path == "/api/conversations" })
    }
    @MainActor func testEditedTargetCannotConsumeOriginalRootTextWithoutReceivingIt() async throws {
        let api = WorkspaceUploadAPI(), workspace = ChatWorkspace(client:api)
        workspace.agentKey = "auto"; workspace.transcript.draft = "original root"
        var reply: CheckedContinuation<[ChatAttachment], Error>?
        api.uploadHandler = { _ in try await withCheckedThrowingContinuation { reply = $0 } }
        let pending = Task { await workspace.pickFiles(self.files) }; await waitFor { reply != nil }
        await workspace.select(17); workspace.transcript.draft = "target edit"
        reply?.resume(returning:[try attachment()])
        let accepted = await pending.value; XCTAssertTrue(accepted)
        XCTAssertEqual(workspace.transcript.draft,"target edit")
        XCTAssertEqual(workspace.transcript.draft(for:nil),"original root")
    }
    @MainActor func testNewDraftLateHandoffPreservesChangedRootAndCurrentConversation() async throws {
        let api = WorkspaceUploadAPI(), workspace = ChatWorkspace(client:api)
        workspace.agentKey = "auto"; workspace.transcript.draft = "captured"
        var reply: CheckedContinuation<[ChatAttachment], Error>?
        api.uploadHandler = { _ in try await withCheckedThrowingContinuation { reply = $0 } }
        let pending = Task { await workspace.pickFiles(self.files) }; await waitFor { reply != nil }
        await workspace.select(8); workspace.transcript.draft = "other"
        workspace.transcript.setDraft("new root",for:nil)
        reply?.resume(returning:[try attachment()])
        let accepted = await pending.value; XCTAssertTrue(accepted)
        XCTAssertEqual(workspace.transcript.selectedID,8)
        XCTAssertEqual(workspace.transcript.draft(for:17),"captured")
        XCTAssertEqual(workspace.transcript.draft(for:nil),"new root")
        XCTAssertEqual(workspace.transcript.draft,"other")
    }
    @MainActor func testCancelOldUploadCannotClearOrPopulateReplacementOrDeliverLateProgress() async throws {
        let api = WorkspaceUploadAPI(), workspace = ChatWorkspace(client:api)
        await workspace.select(7)
        var replies: [CheckedContinuation<[ChatAttachment], Error>] = []
        api.uploadHandler = { _ in try await withCheckedThrowingContinuation { replies.append($0) } }
        let old = Task { await workspace.pickFiles(self.files) }; await waitFor { replies.count == 1 }
        workspace.cancelUpload(for:7)
        XCTAssertFalse(workspace.isUploading)
        let nextFiles = [URL(fileURLWithPath:"/synthetic/new.txt")]
        let next = Task { await workspace.pickFiles(nextFiles) }; await waitFor { replies.count == 2 }
        api.uploads[0].progress?(BackendUploadProgress(sentBodyBytes:99,totalBodyBytes:100))
        replies[0].resume(returning:[try attachment()])
        let oldAccepted = await old.value; XCTAssertFalse(oldAccepted)
        XCTAssertTrue(workspace.isUploading)
        XCTAssertNil(workspace.uploadState(for:7)?.progress)
        replies[1].resume(returning:[try attachment("new.txt")])
        let accepted = await next.value; XCTAssertTrue(accepted)
        XCTAssertEqual(workspace.transcript.attachments,[try attachment("new.txt")])
    }
    @MainActor func testParentCancellationStopAndResetDiscardUncooperativeResults() async throws {
        for action in ["cancel","stop","reset"] {
            let api = WorkspaceUploadAPI(), workspace = ChatWorkspace(client:api)
            await workspace.select(7); workspace.transcript.draft = "keep"
            try workspace.transcript.appendAttachments([attachment("existing")],for:7)
            var reply: CheckedContinuation<[ChatAttachment], Error>?
            api.uploadHandler = { _ in try await withCheckedThrowingContinuation { reply = $0 } }
            let pending = Task { await workspace.pickFiles(self.files) }; await waitFor { reply != nil }
            if action == "cancel" { pending.cancel() } else if action == "stop" { workspace.stop() } else { workspace.reset() }
            reply?.resume(returning:[try attachment()])
            let accepted = await pending.value; XCTAssertFalse(accepted)
            XCTAssertFalse(workspace.isUploading)
            XCTAssertEqual(workspace.transcript.attachments(for:7), action == "reset" ? [] : [try attachment("existing")])
            XCTAssertEqual(workspace.transcript.draft(for:7), action == "reset" ? "" : "keep")
        }
    }
    @MainActor func testLatestProgressIsBoundedAndErrorIsScopedToItsOrigin() async throws {
        let api = WorkspaceUploadAPI(), workspace = ChatWorkspace(client:api)
        await workspace.select(7)
        var reply: CheckedContinuation<[ChatAttachment], Error>?
        api.uploadHandler = { upload in
            for count: Int64 in 1...1000 { upload.progress?(BackendUploadProgress(sentBodyBytes:count,totalBodyBytes:2000)) }
            return try await withCheckedThrowingContinuation { reply = $0 }
        }
        let pending = Task { await workspace.pickFiles(self.files) }; await waitFor { workspace.uploadState(for:7)?.progress?.sentBodyBytes == 1000 }
        await workspace.select(8)
        reply?.resume(throwing:BackendAPIError.status(503))
        let accepted = await pending.value; XCTAssertFalse(accepted)
        XCTAssertNil(workspace.uploadError)
        await workspace.select(7); XCTAssertNotNil(workspace.uploadError)
        XCTAssertFalse(workspace.isUploading)
    }
    @MainActor func testConfirmedDeleteClearsOnlySuccessfulDraftsAndCancelsBothUploads() async throws {
        let api = WorkspaceUploadAPI(), workspace = ChatWorkspace(client:api)
        await workspace.select(7); workspace.transcript.draft = "seven"
        try workspace.transcript.appendAttachments([attachment("a")],for:7)
        try workspace.transcript.appendAttachments([attachment("b")],for:8); workspace.transcript.setDraft("eight",for:8)
        var replies: [Int64:CheckedContinuation<[ChatAttachment], Error>] = [:]
        api.uploadHandler = { upload in try await withCheckedThrowingContinuation { replies[upload.id] = $0 } }
        let first = Task { await workspace.pickFiles(self.files) }; await waitFor { replies[7] != nil }
        await workspace.select(8)
        let second = Task { await workspace.pickFiles(self.files) }; await waitFor { replies[8] != nil }
        let deleted = await workspace.delete(ids:[7,8])
        XCTAssertEqual(deleted.filter(\.ok).map(\.id),[7])
        for id: Int64 in [7,8] { replies[id]?.resume(returning:[try attachment()]) }
        let firstAccepted = await first.value, secondAccepted = await second.value
        XCTAssertFalse(firstAccepted); XCTAssertFalse(secondAccepted)
        XCTAssertTrue(workspace.transcript.attachments(for:7).isEmpty); XCTAssertEqual(workspace.transcript.draft(for:7),"")
        XCTAssertEqual(workspace.transcript.attachments(for:8),[try attachment("b")]); XCTAssertEqual(workspace.transcript.draft,"eight")
    }
    @MainActor func testCancelledCompletionWaitingForListCannotReportSuccessForReplacement() async throws {
        let api = WorkspaceUploadAPI(), workspace = ChatWorkspace(client:api)
        await workspace.select(7)
        var list: CheckedContinuation<BackendHTTPResponse, Error>?
        api.handler = { call in
            if call.path == "/api/conversations" { return try await withCheckedThrowingContinuation { list = $0 } }
            return try ChatTestTransport.response(ChatFixture.page([],cursor:0))
        }
        let old = Task { await workspace.pickFiles(self.files) }; await waitFor { list != nil }
        XCTAssertEqual(workspace.transcript.attachments,[try attachment()])
        workspace.cancelUpload(for:7)
        var replacement: CheckedContinuation<[ChatAttachment], Error>?
        api.uploadHandler = { _ in try await withCheckedThrowingContinuation { replacement = $0 } }
        let next = Task { await workspace.pickFiles([URL(fileURLWithPath:"/synthetic/new.txt")]) }; await waitFor { replacement != nil }
        list?.resume(returning:try ChatTestTransport.response(["conversations":[ChatFixture.conversation(7)]]))
        let oldAccepted = await old.value; XCTAssertFalse(oldAccepted)
        XCTAssertTrue(workspace.isUploading)
        api.handler = nil
        replacement?.resume(returning:[try attachment("new.txt")])
        let accepted = await next.value; XCTAssertTrue(accepted)
        XCTAssertEqual(workspace.transcript.attachments,[try attachment(),try attachment("new.txt")])
    }
    @MainActor func testConfirmedDeleteInvalidatesAnUnconfirmedSendWithoutRestoringCards() async throws {
        let api = WorkspaceUploadAPI(), workspace = ChatWorkspace(client:api)
        await workspace.select(7); workspace.transcript.draft = "discard on delete"
        try workspace.transcript.appendAttachments([attachment()],for:7)
        var send: CheckedContinuation<BackendHTTPResponse, Error>?
        api.handler = { call in
            if call.path == "/api/conversations/7/messages", call.method == "POST" { return try await withCheckedThrowingContinuation { send = $0 } }
            if call.path == "/api/conversations/delete/batch" { return try ChatTestTransport.response(["items":[["id":7,"ok":true]]]) }
            if call.path == "/api/conversations" { return try ChatTestTransport.response(["conversations":[]]) }
            return try ChatTestTransport.response(ChatFixture.page([],cursor:0))
        }
        let pending = Task { await workspace.send() }; await waitFor { send != nil }
        _ = await workspace.delete(ids:[7])
        send?.resume(returning:try ChatTestTransport.response(["status":"accepted"],status:202))
        let accepted = await pending.value; XCTAssertFalse(accepted)
        XCTAssertEqual(workspace.transcript.draft(for:7),""); XCTAssertTrue(workspace.transcript.attachments(for:7).isEmpty)
        XCTAssertNil(workspace.transcript.selectedID)
    }
    @MainActor func testDeletingNewlyCreatedIDBeforeCreateReplyPreventsUpload() async throws {
        let api = WorkspaceUploadAPI(), workspace = ChatWorkspace(client:api)
        workspace.agentKey = "auto"; workspace.transcript.draft = "keep root"
        var create: CheckedContinuation<BackendHTTPResponse, Error>?
        var deletion: CheckedContinuation<BackendHTTPResponse, Error>?
        api.handler = { call in
            if call.path == "/api/conversations", call.method == "POST" { return try await withCheckedThrowingContinuation { create = $0 } }
            if call.path == "/api/conversations/delete/batch" { return try await withCheckedThrowingContinuation { deletion = $0 } }
            return try ChatTestTransport.response(["conversations":[]])
        }
        let picking = Task { await workspace.pickFiles(self.files) }; await waitFor { create != nil }
        let deleting = Task { await workspace.delete(ids:[17]) }; await waitFor { deletion != nil }
        create?.resume(returning:try ChatTestTransport.response(ChatFixture.conversation(17)))
        let accepted = await picking.value; XCTAssertFalse(accepted)
        XCTAssertTrue(api.uploads.isEmpty)
        deletion?.resume(returning:try ChatTestTransport.response(["items":[["id":17,"ok":true]]]))
        _ = await deleting.value
        XCTAssertEqual(workspace.transcript.draft,"keep root")
    }
    @MainActor func testOldListCannotRemoveJustCreatedUploadOwner() async throws {
        let api = WorkspaceUploadAPI(), workspace = ChatWorkspace(client:api)
        workspace.agentKey = "auto"
        var list: CheckedContinuation<BackendHTTPResponse, Error>?
        api.handler = { call in
            if call.path == "/api/conversations", call.method == "GET" { return try await withCheckedThrowingContinuation { list = $0 } }
            if call.path == "/api/conversations" { return try ChatTestTransport.response(ChatFixture.conversation(17)) }
            return try ChatTestTransport.response(ChatFixture.page([],cursor:0))
        }
        let listing = Task { await workspace.transcript.refreshList() }; await waitFor { list != nil }
        let accepted = await workspace.pickFiles(files); XCTAssertTrue(accepted)
        list?.resume(returning:try ChatTestTransport.response(["conversations":[]])); await listing.value
        XCTAssertEqual(workspace.selected?.id,17)
    }
    @MainActor func testStaleCancelActionCannotCancelReplacementOperationForSameConversation() async throws {
        let api = WorkspaceUploadAPI(), workspace = ChatWorkspace(client: api)
        await workspace.select(7)
        var replies: [CheckedContinuation<[ChatAttachment], Error>] = []
        api.uploadHandler = { _ in try await withCheckedThrowingContinuation { replies.append($0) } }
        let first = Task { await workspace.pickFiles(self.files) }
        await waitFor { replies.count == 1 }
        let oldID = try XCTUnwrap(workspace.uploadState(for: 7)?.operationID)
        workspace.cancelUpload(for: 7, operationID: oldID)
        replies[0].resume(returning: [try attachment()])
        let firstAccepted = await first.value; XCTAssertFalse(firstAccepted)
        let replacement = Task { await workspace.pickFiles(self.files) }
        await waitFor { replies.count == 2 }
        let newID = try XCTUnwrap(workspace.uploadState(for: 7)?.operationID)
        XCTAssertNotEqual(oldID, newID)
        workspace.cancelUpload(for: 7, operationID: oldID)
        XCTAssertEqual(workspace.uploadState(for: 7)?.operationID, newID)
        replies[1].resume(returning: [try attachment()])
        let accepted = await replacement.value; XCTAssertTrue(accepted)
        XCTAssertEqual(workspace.transcript.attachments, [try attachment()])
    }

    @MainActor func testKnownLocalUploadFailuresKeepActionableSafeDescription() async throws {
        for error in [ChatUploadBodyError.invalidFile, .invalidFraming, .tooLarge, .changedFile, .readFailure] {
            let api = WorkspaceUploadAPI(), workspace = ChatWorkspace(client: api)
            await workspace.select(7)
            api.uploadHandler = { _ in throw error }
            let accepted = await workspace.pickFiles(files)
            XCTAssertFalse(accepted)
            XCTAssertEqual(workspace.uploadError, error.localizedDescription)
            XCTAssertFalse(workspace.isUploading)
        }
    }

}
