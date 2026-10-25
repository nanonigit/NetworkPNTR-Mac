import XCTest
import AppKit
import SwiftUI
import ArtexCore
@testable import ArtexMac

@MainActor private final class TaskScreenTransport: BackendJSONTransport {
    var paths: [String] = []; var bodies: [Data?] = []
    var reply: CheckedContinuation<BackendHTTPResponse, any Error>?
    var hold = false
    var response: BackendHTTPResponse = .init(status: 503, body: Data())
    func send(method: String, path: String, body: Data?, bearer: String?) async throws -> BackendHTTPResponse {
        paths.append(path); bodies.append(body)
        if hold { return try await withCheckedThrowingContinuation { reply = $0 } }
        return response
    }
}
final class TaskScreenModelTests: XCTestCase {
    private func record(_ id: String? = nil, status: String? = nil) throws -> TaskRecord {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("ArtexCoreTests/Fixtures/task-contract.json")
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        var value = try XCTUnwrap(root["task"] as? [String: Any]); if let id { value["id"] = id }; if let status { value["status"] = status }; return try BackendJSONCoding.decode(TaskRecord.self, from: JSONSerialization.data(withJSONObject: value))
    }
    @MainActor private func submit(_ model: TaskScreenModel) async -> Bool {
        guard let id = model.dialog?.id else { XCTFail("No dialog"); return false }
        return await model.submit(dialogID: id)
    }
    @MainActor private func close(_ model: TaskScreenModel) {
        guard let id = model.dialog?.id else { return }; model.closeDialog(id: id)
    }
    @MainActor private func reached(_ condition: () -> Bool) async throws {
        for _ in 0..<10_000 { if condition() { return }; await Task.yield() }; XCTFail("Missing controlled suspension"); throw CancellationError()
    }
    @MainActor func testRenameKeepsCapturedOwnerDraftAndConfirmedCloseAcrossRefreshFailure() async throws {
        let api = TaskScreenTransport(); let model = TaskScreenModel(store: TaskStore(service: TaskService(client: api)))
        let item = try record(); XCTAssertTrue(model.beginRename(item)); model.renameDraft = "  literal 中文 한국어 {name}  "
        api.hold = true; let save = Task { await submit(model) }; try await reached { api.reply != nil }
        XCTAssertTrue(model.isSubmitting); XCTAssertFalse(model.beginDelete(item))
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(api.bodies[0])) as? [String: Any])
        XCTAssertEqual(body["name"] as? String, "literal 中文 한국어 {name}"); XCTAssertEqual(api.paths, ["/api/tasks/" + item.id])
        api.hold = false
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("ArtexCoreTests/Fixtures/task-contract.json")
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        try XCTUnwrap(api.reply).resume(returning: .init(status: 200, body: JSONSerialization.data(withJSONObject: XCTUnwrap(root["task"]))))
        let succeeded = await save.value; XCTAssertTrue(succeeded); XCTAssertNil(model.dialog); XCTAssertFalse(model.isSubmitting)
        XCTAssertNotNil(model.store.list.failure); XCTAssertNotNil(model.store.lastConfirmation)
    }
    @MainActor func testUnconfirmedDeleteKeepsFlagsAndPreventsRepeatSubmit() async throws {
        let api = TaskScreenTransport(); let model = TaskScreenModel(store: TaskStore(service: TaskService(client: api)))
        XCTAssertTrue(model.beginDelete(try record())); model.deletionOptions.deleteFiles = true
        model.deletionOptions.deleteFindings = true
        let succeeded = await submit(model); XCTAssertFalse(succeeded); XCTAssertNotNil(model.dialog); XCTAssertTrue(model.dialogUncertain)
        let repeated = await submit(model); XCTAssertFalse(repeated); XCTAssertEqual(api.paths.count, 1)
        XCTAssertTrue(model.deletionOptions.deleteFiles); XCTAssertTrue(model.deletionOptions.deleteFindings)
        close(model); XCTAssertNil(model.dialog)
        XCTAssertTrue(model.beginDelete(try record())); XCTAssertFalse(model.deletionOptions.deleteFiles); XCTAssertFalse(model.deletionOptions.deleteAssets)
    }
    @MainActor func testResetDiscardsPendingDialogCompletionAndClearsPrivateInputs() async throws {
        let api = TaskScreenTransport(); let model = TaskScreenModel(store: TaskStore(service: TaskService(client: api)))
        XCTAssertTrue(model.beginRename(try record())); model.renameDraft = "private input"; model.query = "private query"
        api.hold = true; let save = Task { await submit(model) }; try await reached { api.reply != nil }
        model.reset(); XCTAssertNil(model.dialog); XCTAssertEqual(model.renameDraft, ""); XCTAssertEqual(model.query, ""); XCTAssertTrue(model.isSubmitting)
        try XCTUnwrap(api.reply).resume(throwing: CancellationError())
        let succeeded = await save.value; XCTAssertFalse(succeeded); XCTAssertFalse(model.isSubmitting); XCTAssertNil(model.store.mutationFailure)
    }
    @MainActor func testDialogFailureBelongsOnlyToItsSubmission() async throws {
        let api = TaskScreenTransport(); let model = TaskScreenModel(store: TaskStore(service: TaskService(client: api)))
        XCTAssertTrue(model.beginDelete(try record())); _ = await submit(model)
        XCTAssertNotNil(model.dialogFailure)
        close(model); XCTAssertTrue(model.beginRename(try record()))
        XCTAssertNil(model.dialogFailure); XCTAssertFalse(model.dialogUncertain)
        model.renameDraft = "  "
        let sentBefore = api.paths.count
        _ = await submit(model); XCTAssertNotNil(model.dialogFailure); XCTAssertFalse(model.dialogUncertain)
        XCTAssertEqual(api.paths.count, sentBefore); XCTAssertEqual(model.renameDraft, "  ")
    }

    @MainActor func testQueuedConfirmationAndOldCloseCannotTargetReplacementDialog() async throws {
        let api = TaskScreenTransport(); let model = TaskScreenModel(store: TaskStore(service: TaskService(client: api)))
        XCTAssertTrue(model.beginDelete(try record("7")))
        let original = try XCTUnwrap(model.dialog).id
        let queued = Task { await model.submit(dialogID: original) }
        close(model); XCTAssertTrue(model.beginDelete(try record("8")))
        let replacement = try XCTUnwrap(model.dialog).id
        model.closeDialog(id: original)
        _ = await queued.value
        XCTAssertTrue(api.paths.isEmpty); XCTAssertEqual(model.dialog?.id, replacement); XCTAssertFalse(model.dialogUncertain)
    }

    @MainActor func testPinControlAndSelectionUseCapturedIDsWithoutActivation() async throws {
        let api = TaskScreenTransport(); let model = TaskScreenModel(store: TaskStore(service: TaskService(client: api)))
        let item = try record(); api.hold = true
        let pin = Task { await model.togglePin(item) }; try await reached { api.reply != nil }
        await model.control(item); XCTAssertEqual(api.paths.count, 1)
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(api.bodies[0])) as? [String: Any])
        XCTAssertEqual(payload["pinned"] as? Bool, true)
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("ArtexCoreTests/Fixtures/task-contract.json")
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        api.hold = false
        try XCTUnwrap(api.reply).resume(returning: .init(status: 200, body: JSONSerialization.data(withJSONObject: XCTUnwrap(root["task"]))))
        await pin.value
        api.response = .init(status: 200, body: Data(("{\"id\":\"" + item.id + "\",\"paused\":true,\"queued\":false,\"status\":\"paused\"}").utf8))
        await model.control(item); let afterControl = api.paths.count
        await model.control(try record(status: "done")); XCTAssertEqual(api.paths.count, afterControl)
        XCTAssertEqual(api.paths.filter { $0.hasSuffix("/control") }, ["/api/tasks/" + item.id + "/control"])
        XCTAssertFalse(api.paths.contains("/api/active")); XCTAssertFalse(model.busy)
        api.response = .init(status: 503, body: Data())
        model.select("7"); try await reached { model.store.selectedID == "7" && !model.store.detail.isLoading }
        model.stop(); XCTAssertFalse(model.store.isPolling)
    }
    @MainActor func testStoppedManualRefreshCannotStartDetailRefresh() async throws {
        let api = TaskScreenTransport(); let model = TaskScreenModel(store: TaskStore(service: TaskService(client: api)))
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("ArtexCoreTests/Fixtures/task-contract.json")
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        api.response = .init(status: 200, body: try JSONSerialization.data(withJSONObject: XCTUnwrap(root["task"])))
        await model.store.select(id: try record().id)
        api.hold = true
        let read = Task { await model.refresh() }; try await reached { api.reply != nil }
        model.stop(); api.hold = false
        try XCTUnwrap(api.reply).resume(returning: .init(status: 200, body: Data(#"{"tasks":[],"active":""}"#.utf8)))
        await read.value; XCTAssertEqual(api.paths.count, 2); XCTAssertFalse(model.store.detail.isLoading)
    }
    @MainActor func testOffscreenTaskSurfacesConstructInBothLanguagesWithoutChangingDrafts() async throws {
        let api = TaskScreenTransport(); let model = TaskScreenModel(store: TaskStore(service: TaskService(client: api)))
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("ArtexCoreTests/Fixtures/task-contract.json")
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let item = try XCTUnwrap(root["task"])
        api.response = .init(status: 200, body: try JSONSerialization.data(withJSONObject: ["tasks": [item], "active": try record().id]))
        await model.store.refreshList()
        api.response = .init(status: 200, body: try JSONSerialization.data(withJSONObject: item))
        await model.store.select(id: try record().id)
        api.response = .init(status: 503, body: Data())
        defer { model.stop() }
        XCTAssertTrue(model.beginRename(try record())); model.renameDraft = "literal 中文 한국어 {name}"; model.query = "literal"
        let context = try XCTUnwrap(model.dialog).id
        for language in AppLanguage.allCases {
            for content in [AnyView(TasksView(model: model, requestedID: .constant(nil))), AnyView(TaskDialogView(model: model, contextID: context))] {
                let hosting = NSHostingView(rootView: content.environment(\.locale, language.locale))
                hosting.frame = NSRect(x: 0, y: 0, width: 950, height: 680); hosting.layoutSubtreeIfNeeded()
                XCTAssertTrue(hosting.fittingSize.width.isFinite); XCTAssertTrue(hosting.fittingSize.height.isFinite)
                XCTAssertNil(hosting.window)
            }
            XCTAssertEqual(model.renameDraft, "literal 中文 한국어 {name}"); XCTAssertEqual(model.query, "literal")
        }
        close(model); XCTAssertTrue(model.beginDelete(try record())); model.deletionOptions.deleteFiles = true
        let deleting = NSHostingView(rootView: TaskDialogView(model: model, contextID: try XCTUnwrap(model.dialog).id).environment(\.locale, AppLanguage.japanese.locale))
        deleting.layoutSubtreeIfNeeded(); XCTAssertTrue(model.deletionOptions.deleteFiles)
        XCTAssertTrue(api.bodies.allSatisfy { $0 == nil })
    }

    @MainActor func testStaleDialogFieldAndToggleBindingsCannotReadOrOverwriteReplacement() async throws {
        let api = TaskScreenTransport(); let model = TaskScreenModel(store: TaskStore(service: TaskService(client: api)))
        XCTAssertTrue(model.beginRename(try record("7"))); model.renameDraft = "A"
        let original = try XCTUnwrap(model.dialog).id
        let oldName = TaskDialogBindings.rename(model: model, dialogID: original)
        close(model); XCTAssertTrue(model.beginRename(try record("8"))); model.renameDraft = "B"
        oldName.wrappedValue = "late A"; XCTAssertEqual(model.renameDraft, "B"); XCTAssertEqual(oldName.wrappedValue, "")
        let current = TaskDialogBindings.rename(model: model, dialogID: try XCTUnwrap(model.dialog).id)
        current.wrappedValue = "current B"; XCTAssertEqual(model.renameDraft, "current B")
        close(model); XCTAssertTrue(model.beginDelete(try record("7")))
        let oldFlag = TaskDialogBindings.cleanup(model: model, dialogID: try XCTUnwrap(model.dialog).id, key: \.deleteFiles)
        close(model); XCTAssertTrue(model.beginDelete(try record("8")))
        oldFlag.wrappedValue = true; XCTAssertFalse(model.deletionOptions.deleteFiles); XCTAssertFalse(oldFlag.wrappedValue)
        let currentFlag = TaskDialogBindings.cleanup(model: model, dialogID: try XCTUnwrap(model.dialog).id, key: \.deleteFiles)
        currentFlag.wrappedValue = true; XCTAssertTrue(model.deletionOptions.deleteFiles)
        _ = await submit(model); XCTAssertTrue(model.dialogUncertain)
        currentFlag.wrappedValue = false; XCTAssertTrue(model.deletionOptions.deleteFiles)
    }

}
