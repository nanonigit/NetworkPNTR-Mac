import Foundation
import XCTest
@testable import ArtexCore

@MainActor private final class DownloadVault: SessionVault {
    var value: String? = "old.jwt"
    var failsRemoval = false
    func load() throws -> String? { value }
    func save(_ token: String) throws { value = token }
    func remove() throws { if failsRemoval { throw BackendAPIError.secureStorage(-1) }; value = nil }
}
@MainActor private final class DownloadAPI: BackendJSONTransport, BackendAttachmentDownloadTransport {
    var bearers: [String] = []
    var handler: (() async throws -> BackendDownloadResult)?
    var status = 200
    func send(method: String, path: String, body: Data?, bearer: String?) async throws -> BackendHTTPResponse {
        let value: [String: Any]
        switch path {
        case "/api/auth/status": value = ["initialized": true, "setup_token_required": false]
        case "/api/auth/login": value = ["token": "new.jwt"]
        default: value = ["profiles": []]
        }
        return BackendHTTPResponse(status: 200, body: try JSONSerialization.data(withJSONObject: value))
    }
    func downloadDigest(_ attachment: ChatAttachmentDownload, bearer: String) async throws -> BackendDownloadResult {
        bearers.append(bearer)
        if let handler { return try await handler() }
        return BackendDownloadResult(status: status, byteCount: attachment.expectedSize, sha256: "fixture")
    }
}
final class AuthenticatedDownloadTests: XCTestCase {
    func testOnlyPositiveConversationSingleBasenameAndBoundedSizeProduceFixedRoute() throws {
        let attachment = try ChatAttachmentDownload(conversationID: 42, name: "日本語 #?.bin", expectedSize: 7)
        let header = String(decoding: try attachment.request(bearer: "fixture.jwt"), as: UTF8.self)
        XCTAssertTrue(header.hasPrefix("GET /api/workspace/download?path=sessions/conv-42/uploads/"))
        let target = try XCTUnwrap(header.split(separator: " ").dropFirst().first)
        let query = URLComponents(string: "http://localhost" + target)
        XCTAssertEqual(query?.queryItems?.first?.value, "sessions/conv-42/uploads/日本語 #?.bin")
        XCTAssertTrue(header.contains("Accept: application/octet-stream\r\n"))
        XCTAssertTrue(header.contains("Accept-Encoding: identity\r\n"))
        for name in ["", ".", "..", "../file", "a/b", "a\\b", "bad\r\n", "bad\0", String(repeating: "a", count: 256)] {
            XCTAssertThrowsError(try ChatAttachmentDownload(conversationID: 1, name: name, expectedSize: 0))
        }
        for id: Int64 in [0,-1] { XCTAssertThrowsError(try ChatAttachmentDownload(conversationID: id, name: "x", expectedSize: 0)) }
        for size: Int64 in [-1,128 * 1024 * 1024 + 1] { XCTAssertThrowsError(try ChatAttachmentDownload(conversationID: 1, name: "x", expectedSize: size)) }
        for bearer in ["", "bad token", "bad\r\nInjected: yes"] { XCTAssertThrowsError(try attachment.request(bearer: bearer)) }
    }
    @MainActor func testUnauthenticatedAndInvalidRequestsNeverReachCapability() async throws {
        let api = DownloadAPI(), vault = DownloadVault(), session = AuthenticationSession(client: api, vault: vault, setupToken: "fixture")
        do { _ = try await session.authenticatedDownloadDigest(conversationID: 1, name: "x", expectedSize: 0); XCTFail("Unauthenticated") } catch { }
        await session.refresh()
        do { _ = try await session.authenticatedDownloadDigest(conversationID: 1, name: "../x", expectedSize: 0); XCTFail("Invalid name") } catch { }
        XCTAssertTrue(api.bearers.isEmpty)
        let result = try await session.authenticatedDownloadDigest(conversationID: 1, name: "x", expectedSize: 7)
        XCTAssertEqual(result.byteCount, 7)
        XCTAssertEqual(api.bearers, ["old.jwt"])
    }
    @MainActor func test401InvalidatesMemoryEvenWhenVaultFails() async throws {
        let api = DownloadAPI(), vault = DownloadVault(), session = AuthenticationSession(client: api, vault: vault, setupToken: "fixture")
        await session.refresh(); api.status = 401; vault.failsRemoval = true
        do { _ = try await session.authenticatedDownloadDigest(conversationID: 1, name: "x", expectedSize: 0); XCTFail("Vault error") } catch { }
        XCTAssertEqual(session.phase, .needsLogin)
    }
    @MainActor func testOldSuccessAnd401CannotSurviveLogoutOrInvalidateNewLogin() async throws {
        for status in [200,401] {
            let api = DownloadAPI(), vault = DownloadVault(), session = AuthenticationSession(client: api, vault: vault, setupToken: "fixture")
            await session.refresh()
            var reply: CheckedContinuation<BackendDownloadResult, Error>?
            api.handler = { try await withCheckedThrowingContinuation { reply = $0 } }
            let pending = Task { try await session.authenticatedDownloadDigest(conversationID: 1, name: "x", expectedSize: 0) }
            while reply == nil { await Task.yield() }
            session.logout(); await session.login(password: "fixture", agreed: true)
            reply?.resume(returning: BackendDownloadResult(status: status, byteCount: 0, sha256: "fixture"))
            do { _ = try await pending.value; XCTFail("Stale reply") } catch { XCTAssertTrue(error is CancellationError) }
            XCTAssertEqual(session.phase, .authenticated); XCTAssertEqual(vault.value, "new.jwt")
        }
    }
    @MainActor func testCancelledCallerCannotAcceptSuccessfulUncooperativeReply() async throws {
        let api = DownloadAPI(), vault = DownloadVault(), session = AuthenticationSession(client: api, vault: vault, setupToken: "fixture")
        await session.refresh()
        var reply: CheckedContinuation<BackendDownloadResult, Error>?
        api.handler = { try await withCheckedThrowingContinuation { reply = $0 } }
        let pending = Task { try await session.authenticatedDownloadDigest(conversationID: 1, name: "x", expectedSize: 0) }
        while reply == nil { await Task.yield() }
        pending.cancel(); reply?.resume(returning: BackendDownloadResult(status: 200, byteCount: 0, sha256: "fixture"))
        do { _ = try await pending.value; XCTFail("Cancelled reply") } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(session.phase, .authenticated)
    }
    @MainActor func testConcreteClientRequiresReadyVMAndHonorsPrecancel() async throws {
        let provisioning = try GuestProvisioning(transportToken: String(repeating: "a", count: 64), setupToken: String(repeating: "b", count: 64))
        let client: any BackendAttachmentDownloadTransport = BackendJSONClient(runtime: VMController(), provisioning: provisioning)
        let attachment = try ChatAttachmentDownload(conversationID: 1, name: "x", expectedSize: 0)
        do { _ = try await client.downloadDigest(attachment, bearer: "fixture.jwt"); XCTFail("Stopped VM") }
        catch { guard case RuntimeError.integrity("backend not ready") = error else { return XCTFail("Wrong runtime guard") } }
        let pending = Task { try await client.downloadDigest(attachment, bearer: "fixture.jwt") }; pending.cancel()
        do { _ = try await pending.value; XCTFail("Precancel") } catch { XCTAssertTrue(error is CancellationError) }
    }
}
