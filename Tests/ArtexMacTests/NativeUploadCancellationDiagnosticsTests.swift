import Foundation
import XCTest
@testable import ArtexCore
@testable import ArtexMac

@MainActor private final class CancellationFixtureVault: SessionVault {
    func load() throws -> String? { "fixture.jwt" }
    func save(_ token: String) throws { }
    func remove() throws { }
}
@MainActor private final class CancellationFixtureAPI: BackendJSONTransport, BackendMultipartTransport {
    var acceptsCancelledUpload = false
    var failsBeforeStop = false
    var uploads = 0
    var stopped: CheckedContinuation<BackendHTTPResponse, Error>?
    var cleanup: [String] = []
    private func json(_ object: Any) throws -> BackendHTTPResponse {
        BackendHTTPResponse(status: 200, body: try JSONSerialization.data(withJSONObject: object))
    }
    func send(method: String, path: String, body: Data?, bearer: String?) async throws -> BackendHTTPResponse {
        if path == "/api/auth/status" { return try json(["initialized":true,"setup_token_required":false]) }
        if path == "/api/llm/profiles" { return try json(["profiles":[]]) }
        if path == "/api/conversations", method == "POST" { return try json(["id":74,"agent_key":"auto","title":"fixture","created_at":"fixture","updated_at":"fixture"]) }
        if path.hasPrefix("/api/workspace/list?") { return try json(["entries":[]]) }
        if path.hasPrefix("/api/workspace/delete?"), method == "DELETE" {
            let query = URLComponents(string: "http://fixture" + path)
            guard query?.queryItems?.first?.value == "sessions/conv-74/uploads" else { throw BackendAPIError.invalidResponse }
            cleanup.append("files"); return try json(["ok":true])
        }
        if path == "/api/conversations/74", method == "DELETE" { cleanup.append("conversation"); return try json(["deleted":74]) }
        throw BackendAPIError.invalidResponse
    }
    func upload(conversationID: Int64, files: [URL], bearer: String, progress: BackendUploadProgressHandler?) async throws -> BackendHTTPResponse {
        uploads += 1
        let plan = try ChatMultipartPlan(files: files)
        progress?(BackendUploadProgress(sentBodyBytes: 1024 * 1024, totalBodyBytes: plan.contentLength))
        if acceptsCancelledUpload { return try json(["attachments":[]]) }
        if uploads == 1 {
            try await Task.sleep(for: .seconds(30))
            throw BackendAPIError.invalidResponse
        }
        if failsBeforeStop { throw BackendAPIError.status(503) }
        return try await withCheckedThrowingContinuation { stopped = $0 }
    }
}
final class NativeUploadCancellationDiagnosticsTests: XCTestCase {
    @MainActor func testOwnedCancellationFixtureRequiresPartialFailureRestartAndCleanup() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("artex-cancel-fixture-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let api = CancellationFixtureAPI(), session = AuthenticationSession(client: api, vault: CancellationFixtureVault(), setupToken: "fixture")
        await session.refresh()
        var stopCalls = 0
        _ = try await NativeUploadCancellationDiagnostics.run(session: session, directory: root, stopAndRestart: {
            stopCalls += 1
            while api.stopped == nil { await Task.yield() }
            api.stopped?.resume(throwing: CancellationError()); api.stopped = nil
            return session
        })
        XCTAssertEqual(stopCalls, 1); XCTAssertEqual(api.uploads, 2)
        XCTAssertEqual(api.cleanup, ["files", "conversation"])
        let report = try JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent("upload-cancellation-vm.json"))) as! [String: Any]
        XCTAssertEqual(report["owned_files_and_conversation_cleaned"] as? Bool, true)
        XCTAssertNotNil(report["task_cancel"]); XCTAssertNotNil(report["vm_stop"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("upload-cancellation-selected").path))
    }
    @MainActor func testPreStopTransferFailureCannotBeCountedAsVMInterruption() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("artex-pre-stop-failure-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let api = CancellationFixtureAPI(); api.failsBeforeStop = true
        let session = AuthenticationSession(client: api, vault: CancellationFixtureVault(), setupToken: "fixture")
        await session.refresh()
        var stopCalls = 0
        do {
            _ = try await NativeUploadCancellationDiagnostics.run(session: session, directory: root, stopAndRestart: { stopCalls += 1; return session })
            XCTFail("Pre-stop HTTP failure accepted")
        } catch { }
        XCTAssertEqual(stopCalls, 0)
        XCTAssertEqual(api.cleanup, ["files", "conversation"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("upload-cancellation-vm.json").path))
    }
    @MainActor func testUnexpectedUploadSuccessFailsAndStillCleansOwnedFixture() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("artex-cancel-failure-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let api = CancellationFixtureAPI(); api.acceptsCancelledUpload = true
        let session = AuthenticationSession(client: api, vault: CancellationFixtureVault(), setupToken: "fixture")
        await session.refresh()
        do {
            _ = try await NativeUploadCancellationDiagnostics.run(session: session, directory: root, stopAndRestart: { XCTFail("Must not reach VM stop"); return session })
            XCTFail("Unexpected success accepted")
        } catch { }
        XCTAssertEqual(api.cleanup, ["files", "conversation"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("upload-cancellation-vm.json").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("upload-cancellation-selected").path))
    }
}
