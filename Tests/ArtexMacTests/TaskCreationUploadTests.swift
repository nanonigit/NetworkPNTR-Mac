import Foundation
import AppKit
import SwiftUI
import XCTest
@testable import ArtexCore
@testable import ArtexMac

@MainActor private final class DraftUploadAPI: BackendJSONTransport, TaskStagingUploading {
    var drafts: [UUID] = []
    var postCount = 0
    var status = 503
    var created = Data()
    var error: (any Error)?
    var hold = false
    var replies: [CheckedContinuation<[TaskStagedAttachment],Error>] = []
    var progress: [BackendUploadProgressHandler?] = []
    func send(method: String, path: String, body: Data?, bearer: String?) async throws -> BackendHTTPResponse {
        if method == "POST" { postCount += 1; return .init(status:status,body:created) }
        return .init(status:200,body:Data(#"{"tasks":[],"active":""}"#.utf8))
    }
    func attachment(draft: UUID, name: String = "日本.txt") throws -> TaskStagedAttachment {
        let decoder = JSONDecoder(); decoder.userInfo[TaskStagedAttachment.draftKey] = draft
        return try decoder.decode(TaskStagedAttachment.self,from:JSONSerialization.data(withJSONObject:["name":name,"path":"uploads/"+name,"size":1280,"abs":"/state/app/data/drafts/"+draft.uuidString.lowercased()+"/uploads/"+name]))
    }
    func uploadTaskStaging(draftID: UUID, files: [URL], progress: BackendUploadProgressHandler?) async throws -> [TaskStagedAttachment] {
        drafts.append(draftID); self.progress.append(progress)
        progress?(.init(sentBodyBytes:1,totalBodyBytes:10))
        if let error { throw error }
        if hold { return try await withCheckedThrowingContinuation { replies.append($0) } }
        return [try attachment(draft:draftID)]
    }
}

final class TaskCreationUploadTests: XCTestCase {
    private let files = [URL(fileURLWithPath:"/synthetic/selected.txt")]
    @MainActor private func make() -> (DraftUploadAPI,TaskCreationModel) {
        let api = DraftUploadAPI()
        return (api,TaskCreationModel(store:TaskStore(service:TaskService(client:api)),service:TaskCreationService(client:api),uploader:api))
    }
    @MainActor private func reached(_ condition: () -> Bool) async throws {
        for _ in 0..<10_000 { if condition() { return }; await Task.yield() }
        XCTFail("Missing suspension"); throw CancellationError()
    }
    @MainActor func testConfirmedUploadAppendsLatestTextAndKeepsDraftAcrossClose() async throws {
        let (api,model) = make(); let context = try XCTUnwrap(model.open()), draft = model.draftID
        model.update(\.draft.description,value:"initial",contextID:context); model.update(\.draft.goal,value:"goal",contextID:context)
        api.hold = true
        let pending = Task { await model.uploadFiles(self.files,language:.english,contextID:context) }
        try await reached { api.replies.count == 1 && model.uploadProgress != nil }
        XCTAssertTrue(model.isUploading); let blockedSubmit = await model.submit(contextID:context); XCTAssertFalse(blockedSubmit); XCTAssertEqual(api.postCount,0)
        let repeated = await model.uploadFiles(files,language:.japanese,contextID:context); XCTAssertFalse(repeated); XCTAssertEqual(api.drafts.count,1)
        model.update(\.draft.description,value:"edited 한국어",contextID:context)
        api.replies[0].resume(returning:[try api.attachment(draft:draft)])
        let success = await pending.value; XCTAssertTrue(success); XCTAssertFalse(model.isUploading)
        XCTAssertEqual(model.uploadCount,1); XCTAssertTrue(model.form.draft.description.hasPrefix("edited 한국어\n\n[Uploaded files"))
        model.close(contextID:context); let reopened = try XCTUnwrap(model.open())
        XCTAssertEqual(model.draftID,draft); XCTAssertEqual(model.uploadCount,1)
        api.hold = false
        let second = await model.uploadFiles(files,language:.japanese,contextID:reopened); XCTAssertTrue(second)
        XCTAssertEqual(model.uploadCount,2); XCTAssertEqual(api.drafts,[draft,draft]); XCTAssertTrue(model.form.draft.description.contains("【アップロードファイル(絶対パス)】"))
    }
    @MainActor func testCloseCancelsOldOperationAndLateCleanupCannotClearNewUpload() async throws {
        let (api,model) = make(); let old = try XCTUnwrap(model.open()), draft = model.draftID; api.hold = true
        let first = Task { await model.uploadFiles(self.files,language:.english,contextID:old) }
        try await reached { api.replies.count == 1 }
        model.close(contextID:old); XCTAssertFalse(model.isUploading); XCTAssertNotNil(model.uploadFailure)
        let next = try XCTUnwrap(model.open())
        let second = Task { await model.uploadFiles(self.files,language:.japanese,contextID:next) }
        try await reached { api.replies.count == 2 }
        api.progress[0]?(.init(sentBodyBytes:9,totalBodyBytes:10))
        api.replies[0].resume(returning:[try api.attachment(draft:draft,name:"old.txt")])
        let oldSuccess = await first.value; XCTAssertFalse(oldSuccess); XCTAssertTrue(model.isUploading); XCTAssertEqual(model.uploadCount,0)
        api.replies[1].resume(returning:[try api.attachment(draft:draft,name:"new.txt")])
        let newSuccess = await second.value; XCTAssertTrue(newSuccess); XCTAssertEqual(model.uploadCount,1)
        XCTAssertFalse(model.form.draft.description.contains("old.txt")); XCTAssertTrue(model.form.draft.description.contains("new.txt"))
    }
    @MainActor func testResetDiscardAndConfirmedCreateRotateDraftAndIgnoreOldReplies() async throws {
        let (api,model) = make(); var context = try XCTUnwrap(model.open()); let initial = model.draftID
        let uploaded = await model.uploadFiles(files,language:.japanese,contextID:context); XCTAssertTrue(uploaded)
        model.discard(contextID:context); XCTAssertNotEqual(model.draftID,initial); XCTAssertEqual(model.uploadCount,0)
        context = try XCTUnwrap(model.open()); let discarded = model.draftID; api.hold = true
        let old = Task { await model.uploadFiles(self.files,language:.english,contextID:context) }
        try await reached { api.replies.count == 1 }
        model.reset(); XCTAssertNotEqual(model.draftID,discarded); XCTAssertNil(model.context)
        api.replies[0].resume(returning:[try api.attachment(draft:discarded)])
        let oldSuccess = await old.value; XCTAssertFalse(oldSuccess); XCTAssertEqual(model.uploadCount,0); XCTAssertEqual(model.form.draft.description,"")
        context = try XCTUnwrap(model.open()); api.hold = false
        let second = await model.uploadFiles(files,language:.english,contextID:context); XCTAssertTrue(second)
        model.update(\.draft.goal,value:"goal",contextID:context)
        let fixture = URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("ArtexCoreTests/Fixtures/task-contract.json")
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with:Data(contentsOf:fixture)) as? [String:Any])
        api.created = try JSONSerialization.data(withJSONObject:XCTUnwrap(root["task"])); api.status = 201
        let before = model.draftID, created = await model.submit(contextID:context)
        XCTAssertTrue(created); XCTAssertNotEqual(model.draftID,before); XCTAssertEqual(model.uploadCount,0); XCTAssertNil(model.context)
    }
    @MainActor func testPickerFailuresCancellationAndUnknownCreateNeverDispatchUpload() async throws {
        let (api,model) = make(); let context = try XCTUnwrap(model.open())
        model.setPickerPresented(true,contextID:context)
        let blocked = await model.uploadFiles(files,language:.english,contextID:context); XCTAssertFalse(blocked)
        let submit = await model.submit(contextID:context); XCTAssertFalse(submit)
        model.close(contextID:context); XCTAssertNotNil(model.context)
        model.setPickerPresented(false,contextID:UUID()); XCTAssertTrue(model.isPicking)
        model.setPickerPresented(false,contextID:context)
        let empty = await model.uploadFiles([],language:.english,contextID:context); XCTAssertFalse(empty)
        let cancelled = Task { await model.uploadFiles(self.files,language:.english,contextID:context) }; cancelled.cancel()
        let value = await cancelled.value; XCTAssertFalse(value); XCTAssertTrue(api.drafts.isEmpty)
        api.error = BackendAPIError.status(503)
        let failed = await model.uploadFiles(files,language:.english,contextID:context); XCTAssertFalse(failed); XCTAssertEqual(model.uploadCount,0); XCTAssertNotNil(model.uploadFailure)
        XCTAssertFalse(model.isUploading)
        model.update(\.draft.description,value:"d",contextID:context); model.update(\.draft.goal,value:"g",contextID:context)
        let unknown = await model.submit(contextID:context); XCTAssertFalse(unknown); XCTAssertTrue(model.uncertain)
        let before = api.drafts.count
        let forbidden = await model.uploadFiles(files,language:.english,contextID:context); XCTAssertFalse(forbidden); XCTAssertEqual(api.drafts.count,before)
    }
    @MainActor func testParentInjectionBusyAndBilingualAttachmentSectionRetainOwnership() async throws {
        let api = DraftUploadAPI(), store = TaskStore(service:TaskService(client:DraftUploadAPI()))
        let parent = TaskScreenModel(store:store,creationService:TaskCreationService(client:api),stagingUploader:api)
        XCTAssertTrue(parent.beginCreate()); let model = try XCTUnwrap(parent.creation), context = try XCTUnwrap(model.context).id
        XCTAssertTrue(model.uploadsAvailable)
        model.setPickerPresented(true,contextID:context); XCTAssertTrue(parent.busy)
        model.setPickerPresented(false,contextID:context); api.hold = true
        let pending = Task { await model.uploadFiles(self.files,language:.japanese,contextID:context) }
        try await reached { api.replies.count == 1 }
        XCTAssertTrue(parent.busy); let draft = model.draftID
        for language in AppLanguage.allCases {
            let hosting = NSHostingView(rootView:TaskCreateAttachments(model:model,contextID:context).environment(\.locale,language.locale))
            hosting.frame = NSRect(x:0,y:0,width:600,height:180); hosting.layoutSubtreeIfNeeded()
            XCTAssertTrue(hosting.fittingSize.height.isFinite); XCTAssertNil(hosting.window)
            XCTAssertEqual(model.draftID,draft); XCTAssertTrue(model.isUploading)
        }
        api.replies[0].resume(returning:[try api.attachment(draft:draft)])
        let success = await pending.value; XCTAssertTrue(success); XCTAssertFalse(parent.busy)
        let text = Data(model.form.draft.description.utf8)
        for language in AppLanguage.allCases {
            let hosting = NSHostingView(rootView:TaskCreateAttachments(model:model,contextID:context).environment(\.locale,language.locale))
            hosting.frame = NSRect(x:0,y:0,width:600,height:180); hosting.layoutSubtreeIfNeeded()
            XCTAssertEqual(Data(model.form.draft.description.utf8),text)
        }
        parent.reset(); XCTAssertNil(model.context); XCTAssertEqual(model.uploadCount,0)
    }

    @MainActor func testSelectedFileScopesLastUntilUploadCleanupAndStaleSelectionNeverAcquires() async throws {
        let (api,model) = make(); let context = try XCTUnwrap(model.open()); api.hold = true
        var starts = 0, stops = 0
        let access = ChatFileAccess(start: { _ in starts += 1; return true },stop: { _ in stops += 1 })
        let pending = Task { try await TaskCreationUploadSelection.upload(self.files,contextID:context,language:.english,model:model,access:access) }
        try await reached { api.replies.count == 1 }
        XCTAssertEqual(starts,1); XCTAssertEqual(stops,0)
        model.close(contextID:context); XCTAssertEqual(stops,0)
        api.replies[0].resume(returning:[try api.attachment(draft:model.draftID)])
        let success = try await pending.value; XCTAssertFalse(success); XCTAssertEqual(stops,1)
        let stale = try await TaskCreationUploadSelection.upload(files,contextID:context,language:.english,model:model,access:access)
        XCTAssertFalse(stale); XCTAssertEqual(starts,1)
        let next = try XCTUnwrap(model.open()); api.hold = false
        let fresh = try await TaskCreationUploadSelection.upload(files,contextID:next,language:.japanese,model:model,access:access)
        XCTAssertTrue(fresh); XCTAssertEqual(starts,2); XCTAssertEqual(stops,2)
        let unscoped = ChatFileAccess(start: { _ in false },stop: { _ in XCTFail("Unacquired scope released") })
        let normal = try await TaskCreationUploadSelection.upload(files,contextID:next,language:.english,model:model,access:unscoped)
        XCTAssertTrue(normal)
    }

}
