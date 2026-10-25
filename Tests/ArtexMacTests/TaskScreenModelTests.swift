import XCTest
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
    private func record() throws -> TaskRecord {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("ArtexCoreTests/Fixtures/task-contract.json")
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        return try BackendJSONCoding.decode(TaskRecord.self, from: JSONSerialization.data(withJSONObject: XCTUnwrap(root["task"])))
    }
    @MainActor private func reached(_ condition: () -> Bool) async throws {
        for _ in 0..<10_000 { if condition() { return }; await Task.yield() }; XCTFail("Missing controlled suspension"); throw CancellationError()
    }
    @MainActor func testRenameKeepsCapturedOwnerDraftAndConfirmedCloseAcrossRefreshFailure() async throws {
        let api = TaskScreenTransport(); let model = TaskScreenModel(store: TaskStore(service: TaskService(client: api)))
        let item = try record(); XCTAssertTrue(model.beginRename(item)); model.renameDraft = "  literal 中文 한국어 {name}  "
        api.hold = true; let save = Task { await model.submit() }; try await reached { api.reply != nil }
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
        let succeeded = await model.submit(); XCTAssertFalse(succeeded); XCTAssertNotNil(model.dialog); XCTAssertTrue(model.dialogUncertain)
        let repeated = await model.submit(); XCTAssertFalse(repeated); XCTAssertEqual(api.paths.count, 1)
        XCTAssertTrue(model.deletionOptions.deleteFiles); XCTAssertTrue(model.deletionOptions.deleteFindings)
        model.closeDialog(); XCTAssertNil(model.dialog)
        XCTAssertTrue(model.beginDelete(try record())); XCTAssertFalse(model.deletionOptions.deleteFiles); XCTAssertFalse(model.deletionOptions.deleteAssets)
    }
    @MainActor func testResetDiscardsPendingDialogCompletionAndClearsPrivateInputs() async throws {
        let api = TaskScreenTransport(); let model = TaskScreenModel(store: TaskStore(service: TaskService(client: api)))
        XCTAssertTrue(model.beginRename(try record())); model.renameDraft = "private input"; model.query = "private query"
        api.hold = true; let save = Task { await model.submit() }; try await reached { api.reply != nil }
        model.reset(); XCTAssertNil(model.dialog); XCTAssertEqual(model.renameDraft, ""); XCTAssertEqual(model.query, ""); XCTAssertTrue(model.isSubmitting)
        try XCTUnwrap(api.reply).resume(throwing: CancellationError())
        let succeeded = await save.value; XCTAssertFalse(succeeded); XCTAssertFalse(model.isSubmitting); XCTAssertNil(model.store.mutationFailure)
    }
}
