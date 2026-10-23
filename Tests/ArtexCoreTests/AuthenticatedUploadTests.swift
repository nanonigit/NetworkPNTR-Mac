import Foundation
import XCTest
@testable import ArtexCore

@MainActor private final class UploadVault: SessionVault {
    var value: String? = "old.jwt"
    var failsRemoval = false
    func load() throws -> String? { value }
    func save(_ token: String) throws { value = token }
    func remove() throws { if failsRemoval { throw BackendAPIError.secureStorage(-1) }; value = nil }
}
@MainActor private final class UploadAPI: BackendJSONTransport, BackendMultipartTransport {
    var bearers: [String] = []
    var selected: [[URL]] = []
    var ids: [Int64] = []
    var nextStatus = 200
    var progressSink: BackendUploadProgressHandler?
    var handler: (() async throws -> BackendHTTPResponse)?
    func send(method: String, path: String, body: Data?, bearer: String?) async throws -> BackendHTTPResponse {
        let value: [String: Any]
        switch path {
        case "/api/auth/status": value = ["initialized": true, "setup_token_required": false]
        case "/api/auth/login": value = ["token": "new.jwt"]
        case "/api/llm/profiles": value = ["profiles": []]
        default: throw BackendAPIError.invalidResponse
        }
        return BackendHTTPResponse(status: 200, body: try JSONSerialization.data(withJSONObject: value))
    }
    func upload(conversationID: Int64, files: [URL], bearer: String, progress: BackendUploadProgressHandler? = nil) async throws -> BackendHTTPResponse {
        bearers.append(bearer); selected.append(files); ids.append(conversationID)
        progressSink = progress
        progress?(BackendUploadProgress(sentBodyBytes: 1, totalBodyBytes: 100))
        if let handler { return try await handler() }
        return BackendHTTPResponse(status: nextStatus, body: Data("{}".utf8))
    }
}
private final class UploadObservedProgress: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    func record(_ value: BackendUploadProgress) { lock.lock(); count += 1; lock.unlock() }
    var received: Int { lock.lock(); defer { lock.unlock() }; return count }
}
final class AuthenticatedUploadTests: XCTestCase {
    private let selected = [URL(fileURLWithPath: "/synthetic/selected.txt")]
    @MainActor func testAuthenticationAndInputValidationPrecedeUploadCapability() async throws {
        let api = UploadAPI(), vault = UploadVault(), session = AuthenticationSession(client: api, vault: vault, setupToken: "fixture")
        do { _ = try await session.authenticatedUpload(conversationID: 1, files: selected); XCTFail("Unauthenticated upload") }
        catch { }
        XCTAssertTrue(api.bearers.isEmpty)
        await session.refresh()
        for id: Int64 in [0,-1] {
            do { _ = try await session.authenticatedUpload(conversationID: id, files: selected); XCTFail("Invalid ID") } catch { }
        }
        do { _ = try await session.authenticatedUpload(conversationID: 1, files: []); XCTFail("Empty selection") } catch { }
        XCTAssertTrue(api.bearers.isEmpty)
        let response = try await session.authenticatedUpload(conversationID: 42, files: selected)
        XCTAssertEqual(response.status, 200)
        XCTAssertEqual(api.bearers, ["old.jwt"]); XCTAssertEqual(api.selected, [selected]); XCTAssertEqual(api.ids, [42])
    }
    @MainActor func testUnauthorizedUploadInvalidatesMemoryEvenIfKeychainRemovalFails() async throws {
        let api = UploadAPI(), vault = UploadVault(), session = AuthenticationSession(client: api, vault: vault, setupToken: "fixture")
        await session.refresh(); api.nextStatus = 401; vault.failsRemoval = true
        do { _ = try await session.authenticatedUpload(conversationID: 1, files: selected); XCTFail("Secure storage error") } catch { }
        XCTAssertEqual(session.phase, .needsLogin)
        do { _ = try await session.authenticatedUpload(conversationID: 1, files: selected); XCTFail("Expired auth reused") } catch { }
        XCTAssertEqual(api.bearers.count, 1)
    }
    @MainActor func testOldUnauthorizedUploadCannotEraseNewLogin() async throws {
        let api = UploadAPI(), vault = UploadVault(), session = AuthenticationSession(client: api, vault: vault, setupToken: "fixture")
        await session.refresh()
        var reply: CheckedContinuation<BackendHTTPResponse, Error>?
        api.handler = { try await withCheckedThrowingContinuation { reply = $0 } }
        let pending = Task { @MainActor in try await session.authenticatedUpload(conversationID: 1, files: self.selected) }
        while reply == nil { await Task.yield() }
        session.logout(); await session.login(password: "fixture-password", agreed: true)
        XCTAssertEqual(vault.value, "new.jwt")
        reply?.resume(returning: BackendHTTPResponse(status: 401, body: Data()))
        do { _ = try await pending.value; XCTFail("Stale upload accepted") } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(session.phase, .authenticated); XCTAssertEqual(vault.value, "new.jwt")
        api.handler = nil
        _ = try await session.authenticatedUpload(conversationID: 2, files: selected)
        XCTAssertEqual(api.bearers, ["old.jwt", "new.jwt"])
    }
    @MainActor func testUploadSuccessAfterLogoutCannotReturnToOldCaller() async throws {
        let api = UploadAPI(), vault = UploadVault(), session = AuthenticationSession(client: api, vault: vault, setupToken: "fixture")
        await session.refresh()
        var reply: CheckedContinuation<BackendHTTPResponse, Error>?
        api.handler = { try await withCheckedThrowingContinuation { reply = $0 } }
        let pending = Task { @MainActor in try await session.authenticatedUpload(conversationID: 1, files: self.selected) }
        while reply == nil { await Task.yield() }
        session.logout()
        reply?.resume(returning: BackendHTTPResponse(status: 200, body: Data("{}".utf8)))
        do { _ = try await pending.value; XCTFail("Stale success accepted") } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(session.phase, .needsLogin); XCTAssertNil(vault.value)
    }
    @MainActor func testProgressStopsAfterCompletionOrLogoutAndNewLogin() async throws {
        let api = UploadAPI(), vault = UploadVault(), session = AuthenticationSession(client: api, vault: vault, setupToken: "fixture")
        let values = UploadObservedProgress(), event = BackendUploadProgress(sentBodyBytes: 2, totalBodyBytes: 100)
        await session.refresh()
        _ = try await session.authenticatedUpload(conversationID: 1, files: selected, progress: { values.record($0) })
        api.progressSink?(event)
        XCTAssertEqual(values.received, 1)
        var reply: CheckedContinuation<BackendHTTPResponse, Error>?
        api.handler = { try await withCheckedThrowingContinuation { reply = $0 } }
        let pending = Task { try await session.authenticatedUpload(conversationID: 1, files: self.selected, progress: { values.record($0) }) }
        while reply == nil { await Task.yield() }
        XCTAssertEqual(values.received, 2)
        session.logout(); await session.login(password: "fixture", agreed: true)
        api.progressSink?(event)
        XCTAssertEqual(values.received, 2)
        reply?.resume(returning: BackendHTTPResponse(status: 200, body: Data()))
        do { _ = try await pending.value; XCTFail("Stale reply") } catch { XCTAssertTrue(error is CancellationError) }
        api.progressSink?(event)
        XCTAssertEqual(values.received, 2)
    }
    @MainActor func testCancelledUncooperativeUploadCannotReturnSuccessOrFurtherProgress() async throws {
        let api = UploadAPI(), session = AuthenticationSession(client: api, vault: UploadVault(), setupToken: "fixture")
        let values = UploadObservedProgress()
        await session.refresh()
        var reply: CheckedContinuation<BackendHTTPResponse, Error>?
        api.handler = { try await withCheckedThrowingContinuation { reply = $0 } }
        let pending = Task { try await session.authenticatedUpload(conversationID: 1, files: self.selected, progress: { values.record($0) }) }
        while reply == nil { await Task.yield() }
        pending.cancel()
        api.progressSink?(BackendUploadProgress(sentBodyBytes: 2, totalBodyBytes: 100))
        XCTAssertEqual(values.received, 1)
        reply?.resume(returning: BackendHTTPResponse(status: 200, body: Data()))
        do { _ = try await pending.value; XCTFail("Cancelled success") } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(session.phase, .authenticated)
    }
    @MainActor func testCancellationFromProgressCallbackDoesNotDeadlockGate() async throws {
        let api = UploadAPI(), session = AuthenticationSession(client: api, vault: UploadVault(), setupToken: "fixture")
        await session.refresh()
        let pending = Task {
            try await session.authenticatedUpload(conversationID: 1, files: self.selected, progress: { _ in
                withUnsafeCurrentTask { $0?.cancel() }
            })
        }
        do { _ = try await pending.value; XCTFail("Cancelled callback success") } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(session.phase, .authenticated)
    }
    @MainActor func testNativeClientPreflightsLimitBeforeAttemptingStoppedVMConnection() async throws {
        let runtime = VMController()
        let provisioning = try GuestProvisioning(transportToken: String(repeating: "a", count: 64), setupToken: String(repeating: "b", count: 64))
        let client: any BackendMultipartTransport = BackendJSONClient(runtime: runtime, provisioning: provisioning)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("artex-upload-preflight-" + UUID().uuidString)
        XCTAssertTrue(FileManager.default.createFile(atPath: url.path, contents: nil))
        defer { try? FileManager.default.removeItem(at: url) }
        let writer = try FileHandle(forWritingTo: url)
        try writer.truncate(atOffset: 128 * 1024 * 1024)
        do { _ = try await client.upload(conversationID: 1, files: [url], bearer: "fixture.jwt"); XCTFail("Oversized file accepted") }
        catch { guard case ChatUploadBodyError.tooLarge = error else { return XCTFail("Preflight must reject before VM access") } }
        try writer.truncate(atOffset: 0); try writer.close()
        do { _ = try await client.upload(conversationID: 1, files: [url], bearer: "fixture.jwt"); XCTFail("Stopped VM accepted") }
        catch { guard case RuntimeError.integrity("backend not ready") = error else { return XCTFail("Expected stopped VM boundary") } }
        XCTAssertEqual(runtime.state, .idle); XCTAssertFalse(runtime.hasMachine)
    }
    @MainActor func testNativeClientCancelledTaskDoesNotStartPreflightOrConnect() async throws {
        let provisioning = try GuestProvisioning(transportToken: String(repeating: "a", count: 64), setupToken: String(repeating: "b", count: 64))
        let client: any BackendMultipartTransport = BackendJSONClient(runtime: VMController(), provisioning: provisioning)
        let pending = Task { @MainActor in
            withUnsafeCurrentTask { $0?.cancel() }
            return try await client.upload(conversationID: 1, files: self.selected, bearer: "fixture.jwt")
        }
        do { _ = try await pending.value; XCTFail("Cancelled transfer started") }
        catch { XCTAssertTrue(error is CancellationError) }
    }

}
