import CryptoKit
import Foundation
import XCTest
@testable import NetworkPNTRCore

@MainActor private final class EvidenceSessionVault: SessionVault {
    var value: String? = "old.jwt"
    var failsRemoval = false
    func load() throws -> String? { value }
    func save(_ token: String) throws { value = token }
    func remove() throws { if failsRemoval { throw BackendAPIError.secureStorage(-1) }; value = nil }
}
@MainActor private final class EvidenceSessionAPI: BackendJSONTransport, BackendEvidenceDownloadTransport {
    var bearers: [String] = []
    var handler: (() async throws -> EvidenceExportReceipt)?
    func send(method: String, path: String, body: Data?, bearer: String?) async throws -> BackendHTTPResponse {
        let value: [String: Any]
        switch path {
        case "/api/auth/status": value = ["initialized": true, "setup_token_required": false]
        case "/api/auth/login": value = ["token": "new.jwt"]
        default: value = ["profiles": []]
        }
        return BackendHTTPResponse(status: 200, body: try JSONSerialization.data(withJSONObject: value))
    }
    func stageEvidence(_ manifest: FindingEvidenceDownload, destination: EvidenceExportDestination, bearer: String) async throws -> EvidenceExportReceipt {
        bearers.append(bearer)
        return try await XCTUnwrap(handler)()
    }
}

final class AuthenticatedEvidenceExportTests: XCTestCase {
    private let bytes = Data([0, 255, 13, 10, 0, 97])
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("artex-auth-evidence-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        return url
    }
    private func spec() throws -> FindingEvidenceDownload {
        try FindingEvidenceDownload(findingID: "1", bindingID: "7", side: .response, expectedSize: Int64(bytes.count), expectedSHA256: SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined())
    }
    @MainActor private func receipt(_ destination: EvidenceExportDestination, validate: @escaping @MainActor () throws -> Void = {}) throws -> EvidenceExportReceipt {
        let manifest = try spec(), writer = try EvidenceExportWriter(destination: destination, request: manifest)
        try writer.append(bytes)
        let result = BackendDownloadResult(status: 200, byteCount: Int64(bytes.count), sha256: manifest.expectedSHA256)
        return EvidenceExportReceipt(response: EvidenceDownloadResponse(result: result, file: try writer.finish(response: result)), validate: validate)
    }
    @MainActor func testCurrentSessionStagesThenCommitsExactBytesOnlyOnce() async throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("saved.bin"), destination = try EvidenceExportDestination(newFileURL: url)
        let api = EvidenceSessionAPI(), vault = EvidenceSessionVault(), session = AuthenticationSession(client: api, vault: vault, setupToken: "fixture")
        await session.refresh(); api.handler = { try self.receipt(destination) }
        let export = try await session.authenticatedEvidenceExport(try spec(), destination: destination)
        XCTAssertEqual(api.bearers, ["old.jwt"]); XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        let saved = try export.commit()
        XCTAssertEqual(try Data(contentsOf: saved.url), bytes); XCTAssertEqual(saved.sha256, try spec().expectedSHA256)
        XCTAssertThrowsError(try export.commit()); try export.discard()
        XCTAssertEqual(try Data(contentsOf: url), bytes)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), ["saved.bin"])
    }
    @MainActor func testUnauthenticatedAndPrecancelledNeverCallTransportOrCreateStaging() async throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let destination = try EvidenceExportDestination(newFileURL: root.appendingPathComponent("saved.bin"))
        let api = EvidenceSessionAPI(), session = AuthenticationSession(client: api, vault: EvidenceSessionVault(), setupToken: "fixture")
        do { _ = try await session.authenticatedEvidenceExport(try spec(), destination: destination); XCTFail("Authentication required") } catch { }
        await session.refresh()
        let pending = Task { try await session.authenticatedEvidenceExport(try spec(), destination: destination) }; pending.cancel()
        do { _ = try await pending.value; XCTFail("Cancelled") } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertTrue(api.bearers.isEmpty); XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
    }
    @MainActor func testNonSuccessAndMalformedSuccessDiscardStagedFile() async throws {
        for status in [200, 403, 500] {
            let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
            let destination = try EvidenceExportDestination(newFileURL: root.appendingPathComponent("saved.bin"))
            let api = EvidenceSessionAPI(), session = AuthenticationSession(client: api, vault: EvidenceSessionVault(), setupToken: "fixture")
            await session.refresh()
            api.handler = {
                let manifest = try self.spec(), writer = try EvidenceExportWriter(destination: destination, request: manifest)
                try writer.append(self.bytes)
                let correct = BackendDownloadResult(status: 200, byteCount: Int64(self.bytes.count), sha256: manifest.expectedSHA256)
                let file = try writer.finish(response: correct)
                let result = BackendDownloadResult(status: status, byteCount: 0, sha256: "wrong")
                return EvidenceExportReceipt(response: EvidenceDownloadResponse(result: result, file: file))
            }
            do { _ = try await session.authenticatedEvidenceExport(try spec(), destination: destination); XCTFail("Invalid reply") } catch { }
            XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
            XCTAssertEqual(session.phase, .authenticated)
        }
    }
    @MainActor func testCurrent401ExpiresAuthenticationEvenWhenVaultRemovalFails() async throws {
        for fail in [false, true] {
            let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
            let destination = try EvidenceExportDestination(newFileURL: root.appendingPathComponent("saved.bin"))
            let api = EvidenceSessionAPI(), vault = EvidenceSessionVault(), session = AuthenticationSession(client: api, vault: vault, setupToken: "fixture")
            await session.refresh(); vault.failsRemoval = fail
            api.handler = { EvidenceExportReceipt(response: EvidenceDownloadResponse(result: .init(status: 401, byteCount: 0, sha256: ""), file: nil)) }
            do { _ = try await session.authenticatedEvidenceExport(try spec(), destination: destination); XCTFail("401") } catch { }
            XCTAssertEqual(session.phase, .needsLogin); XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
        }
    }
    @MainActor func testUncooperativeOld200And401AreDiscardedWithoutExpiringNewSession() async throws {
        for status in [200, 401] {
            let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
            let destination = try EvidenceExportDestination(newFileURL: root.appendingPathComponent("saved.bin"))
            let api = EvidenceSessionAPI(), vault = EvidenceSessionVault(), session = AuthenticationSession(client: api, vault: vault, setupToken: "fixture")
            await session.refresh()
            var reply: CheckedContinuation<EvidenceExportReceipt, Error>?
            api.handler = { try await withCheckedThrowingContinuation { reply = $0 } }
            let pending = Task { try await session.authenticatedEvidenceExport(try spec(), destination: destination) }
            while reply == nil { await Task.yield() }
            session.logout(); await session.login(password: "fixture", agreed: true)
            let response = status == 200 ? try receipt(destination) : EvidenceExportReceipt(response: EvidenceDownloadResponse(result: .init(status: 401, byteCount: 0, sha256: ""), file: nil))
            reply?.resume(returning: response)
            do { _ = try await pending.value; XCTFail("Stale reply") } catch { XCTAssertTrue(error is CancellationError) }
            XCTAssertEqual(session.phase, .authenticated); XCTAssertEqual(vault.value, "new.jwt")
            XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
        }
    }
    @MainActor func testCancelledCallerDiscardsSuccessfulUncooperativeReply() async throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let destination = try EvidenceExportDestination(newFileURL: root.appendingPathComponent("saved.bin"))
        let api = EvidenceSessionAPI(), session = AuthenticationSession(client: api, vault: EvidenceSessionVault(), setupToken: "fixture")
        await session.refresh()
        var reply: CheckedContinuation<EvidenceExportReceipt, Error>?
        api.handler = { try await withCheckedThrowingContinuation { reply = $0 } }
        let pending = Task { try await session.authenticatedEvidenceExport(try spec(), destination: destination) }
        while reply == nil { await Task.yield() }
        pending.cancel(); reply?.resume(returning: try receipt(destination))
        do { _ = try await pending.value; XCTFail("Cancelled reply") } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
    }
    @MainActor func testLogoutAfterTransferAndDuringUIValidationPreventsPublication() async throws {
        for during in [false, true] {
            let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
            let destination = try EvidenceExportDestination(newFileURL: root.appendingPathComponent("saved.bin"))
            let api = EvidenceSessionAPI(), session = AuthenticationSession(client: api, vault: EvidenceSessionVault(), setupToken: "fixture")
            await session.refresh(); api.handler = { try self.receipt(destination) }
            let export = try await session.authenticatedEvidenceExport(try spec(), destination: destination)
            if !during { session.logout() }
            XCTAssertThrowsError(try export.commit(validate: { if during { session.logout() } })) { XCTAssertTrue($0 is CancellationError) }
            XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
        }
    }
    @MainActor func testUIOrVMGuardFailureAndCancelledPublishDiscardStaging() async throws {
        for mode in 0..<3 {
            let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
            let destination = try EvidenceExportDestination(newFileURL: root.appendingPathComponent("saved.bin"))
            var runtimeActive = true
            let export = try receipt(destination, validate: { if !runtimeActive { throw CancellationError() } })
            if mode == 0 { runtimeActive = false; XCTAssertThrowsError(try export.commit()) }
            else if mode == 1 { XCTAssertThrowsError(try export.commit(validate: { throw CancellationError() })) }
            else {
                let pending = Task { try export.commit() }; pending.cancel()
                do { _ = try await pending.value; XCTFail("Cancelled commit") } catch { XCTAssertTrue(error is CancellationError) }
            }
            XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
            XCTAssertThrowsError(try export.commit()); try export.discard()
        }
    }
    @MainActor func testReceiptDiscardDuringUIValidationCannotClearGuardsAndPublish() throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let destination = try EvidenceExportDestination(newFileURL: root.appendingPathComponent("saved.bin"))
        let export = try receipt(destination, validate: { throw CancellationError() })
        XCTAssertThrowsError(try export.commit(validate: { try export.discard() })) { XCTAssertTrue($0 is CancellationError) }
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
    }
    @MainActor func testRevokedVM401DoesNotExpireCurrentAuthentication() async throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let destination = try EvidenceExportDestination(newFileURL: root.appendingPathComponent("saved.bin"))
        let api = EvidenceSessionAPI(), vault = EvidenceSessionVault(), session = AuthenticationSession(client: api, vault: vault, setupToken: "fixture")
        await session.refresh()
        api.handler = { EvidenceExportReceipt(response: EvidenceDownloadResponse(result: .init(status: 401, byteCount: 0, sha256: ""), file: nil), validate: { throw CancellationError() }) }
        do { _ = try await session.authenticatedEvidenceExport(try spec(), destination: destination); XCTFail("Revoked VM reply") } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(session.phase, .authenticated); XCTAssertEqual(vault.value, "old.jwt")
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
    }
    @MainActor func testConcreteClientHonorsStoppedVMInvalidBearerAndPrecancel() async throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let destination = try EvidenceExportDestination(newFileURL: root.appendingPathComponent("saved.bin"))
        let provisioning = try GuestProvisioning(transportToken: String(repeating: "a", count: 64), setupToken: String(repeating: "b", count: 64))
        let client: any BackendEvidenceDownloadTransport = BackendJSONClient(runtime: VMController(), provisioning: provisioning)
        do { _ = try await client.stageEvidence(try spec(), destination: destination, bearer: "fixture.jwt"); XCTFail("Stopped VM") }
        catch { guard case RuntimeError.integrity("backend not ready") = error else { return XCTFail("Wrong runtime guard") } }
        do { _ = try await client.stageEvidence(try spec(), destination: destination, bearer: "bad\r\n"); XCTFail("Invalid bearer") } catch { }
        let pending = Task { try await client.stageEvidence(try spec(), destination: destination, bearer: "fixture.jwt") }; pending.cancel()
        do { _ = try await pending.value; XCTFail("Cancelled") } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
    }
}
