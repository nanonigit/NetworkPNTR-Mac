import CryptoKit
import Foundation
import XCTest
@testable import NetworkPNTRCore

@MainActor private final class BlobAPI: BackendJSONTransport, BackendTrafficBlobDownloadTransport {
    var paths: [String] = [], bearers: [String] = []
    var value: [String: Any] = [:]
    var status = 200
    var stage: (@MainActor (TrafficBlobDownload, EvidenceExportDestination) async throws -> EvidenceExportReceipt)?
    func send(method: String, path: String, body: Data?, bearer: String?) async throws -> BackendHTTPResponse {
        paths.append(path)
        let object: Any
        if path == "/api/auth/status" { object = ["initialized": true, "setup_token_required": false] }
        else if path == "/api/auth/login" { object = ["token": "new.fixture.jwt"] }
        else if path == "/api/llm/profiles" { object = ["profiles": []] }
        else { object = value }
        return .init(status: path.hasPrefix("/api/traffic/") ? status : 200, body: try JSONSerialization.data(withJSONObject: object))
    }
    func stageTrafficBlob(_ manifest: TrafficBlobDownload, destination: EvidenceExportDestination, bearer: String) async throws -> EvidenceExportReceipt {
        bearers.append(bearer); return try await XCTUnwrap(stage)(manifest, destination)
    }
}
@MainActor private final class BlobVault: SessionVault {
    var token: String? = "old.fixture.jwt"
    var fail = false
    func load() throws -> String? { token }
    func save(_ token: String) throws { self.token = token }
    func remove() throws { if fail { throw BackendAPIError.secureStorage(-1) }; token = nil }
}

@MainActor final class TrafficBlobDownloadTests: XCTestCase {
    private let id = "\u{FEFF}e\u{301}+中文 한국어?#&"
    private let bytes = Data([0, 255, 13, 10, 97])
    private var bodyHash: String { ArtifactIntegrity.sha256(bytes) }
    private func manifest(_ size: Int64? = nil) throws -> TrafficBlobDownload {
        try TrafficBlobDownload(trafficID: id, side: .response, expectedSize: size ?? Int64(bytes.count), expectedSHA256: bodyHash)
    }
    // Decode percent bytes independently; Foundation's String decoding can consume a leading UTF8 BOM.
    private func queryBytes(_ path: String) throws -> [String: Data] {
        let components = try XCTUnwrap(URLComponents(string: path))
        let query = try XCTUnwrap(components.percentEncodedQuery)
        var result: [String: Data] = [:]
        for item in query.split(separator: "&") {
            let pair = item.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            XCTAssertEqual(pair.count, 2)
            let raw = Array(pair[1].utf8)
            var decoded = Data(), cursor = 0
            while cursor < raw.count {
                if raw[cursor] == 37 {
                    XCTAssertLessThan(cursor + 2, raw.count)
                    let hex = String(decoding: raw[(cursor + 1)...(cursor + 2)], as: UTF8.self)
                    decoded.append(try XCTUnwrap(UInt8(hex, radix: 16))); cursor += 3
                } else {
                    XCTAssertNotEqual(raw[cursor], 43, "A literal plus would become a space in the Go server")
                    decoded.append(raw[cursor]); cursor += 1
                }
            }
            result[String(pair[0])] = decoded
        }
        return result
    }

    private func directory() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("artex-blob-native-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false); return root
    }
    private func receipt(_ manifest: TrafficBlobDownload, _ destination: EvidenceExportDestination,
                         validate: @escaping @MainActor () throws -> Void = {}) throws -> EvidenceExportReceipt {
        let writer = try EvidenceExportWriter(destination: destination, request: manifest); try writer.append(bytes)
        let result = BackendDownloadResult(status: 200, byteCount: Int64(bytes.count), sha256: bodyHash)
        return EvidenceExportReceipt(response: .init(result: result, file: try writer.finish(response: result)), validate: validate)
    }
    func testExportSessionGenerationChangesAcrossLogoutRelogin() async throws {
        let session = AuthenticationSession(client: BlobAPI(), vault: BlobVault(), setupToken: "fixture")
        XCTAssertNil(session.exportSessionGeneration)
        await session.refresh()
        let original = try XCTUnwrap(session.exportSessionGeneration)
        session.logout(); XCTAssertNil(session.exportSessionGeneration)
        await session.login(password: "fixture", agreed: true)
        XCTAssertEqual(session.phase, .authenticated)
        XCTAssertNotEqual(session.exportSessionGeneration, original)
    }
    func testMetadataUsesFixedEscapedRouteAndLiteralIdentity() async throws {
        let api = BlobAPI(); api.value = ["id": id, "side": "response", "hash": bodyHash, "size": 9007199254740993 as Int64]
        let value = try await TrafficService(client: api).blobDownload(id: id, side: .response)
        XCTAssertEqual(Data(value.trafficID.utf8), Data(id.utf8)); XCTAssertEqual(value.expectedSize, 9007199254740993)
        let path = try XCTUnwrap(api.paths.first), parts = try XCTUnwrap(URLComponents(string: path))
        XCTAssertEqual(parts.path, "/api/traffic/blob-metadata")
        XCTAssertEqual(try queryBytes(path)["id"], Data(id.utf8))
        XCTAssertEqual(parts.queryItems?.first { $0.name == "side" }?.value, "response")
        let request = String(decoding: try value.request(bearer: "fixture.jwt"), as: UTF8.self)
        XCTAssertTrue(request.hasPrefix("GET /api/traffic/blob?hash=" + bodyHash + " HTTP/1.1\r\n"))
        XCTAssertTrue(request.contains("Accept: application/octet-stream\r\nAccept-Encoding: identity\r\n"))
        XCTAssertFalse(request.contains(id)); XCTAssertFalse(value.suggestedFilename.contains(id))
        XCTAssertThrowsError(try value.request(bearer: "bad\r\nvalue")); XCTAssertThrowsError(try value.request(bearer: ""))
    }
    func testInvalidScopeAndMalformedOrMismatchedMetadataAreRejected() async throws {
        for mode in 0..<8 {
            let api = BlobAPI(); api.value = ["id": id, "side": "response", "hash": bodyHash, "size": bytes.count]
            switch mode {
            case 0: api.value["id"] = id.precomposedStringWithCanonicalMapping
            case 1: api.value["side"] = "request"
            case 2: api.value["hash"] = bodyHash.uppercased()
            case 3: api.value["size"] = -1
            case 4: api.value["size"] = 1.5
            case 5: api.value["hash"] = String(repeating: "g", count: 64)
            case 6: api.status = 404
            default: api.status = 503
            }
            do { _ = try await TrafficService(client: api).blobDownload(id: id, side: .response); XCTFail("Bad metadata \(mode)") } catch { }
        }
        for invalid in ["", "x\n", String(repeating: "中", count: 1000)] {
            let api = BlobAPI()
            do { _ = try await TrafficService(client: api).blobDownload(id: invalid, side: .request); XCTFail("Bad path") } catch { }
            XCTAssertTrue(api.paths.isEmpty)
        }
        XCTAssertThrowsError(try TrafficBlobDownload(trafficID: id, side: .request, expectedSize: -1, expectedSHA256: bodyHash))
    }
    func testBlobWriterRealBinaryNoClobberAndMismatchCleanup() throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("saved.bin"), spec = try manifest()
        let writer = try EvidenceExportWriter(destination: .init(newFileURL: url), request: spec); try writer.append(bytes)
        let saved = try writer.finish(response: .init(status: 200, byteCount: Int64(bytes.count), sha256: bodyHash)).commit()
        XCTAssertEqual(try Data(contentsOf: saved.url), bytes); XCTAssertTrue(saved.stagingCleanupComplete)
        XCTAssertThrowsError(try EvidenceExportDestination(newFileURL: url))
        let failed = try EvidenceExportWriter(destination: .init(newFileURL: root.appendingPathComponent("bad.bin")), request: spec)
        try failed.append(bytes); XCTAssertThrowsError(try failed.finish(response: .init(status: 200, byteCount: 1, sha256: bodyHash))); try failed.discard()
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), ["saved.bin"])
    }
    func testAuthenticatedBlobStagesAndCommitsOnlyOnce() async throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let api = BlobAPI(), session = AuthenticationSession(client: api, vault: BlobVault(), setupToken: "fixture")
        await session.refresh(); api.stage = { try self.receipt($0, $1) }
        let url = root.appendingPathComponent("saved.bin")
        let export = try await session.authenticatedTrafficBlobExport(try manifest(), destination: .init(newFileURL: url))
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path)); XCTAssertEqual(api.bearers, ["old.fixture.jwt"])
        let saved = try export.commit(); XCTAssertEqual(try Data(contentsOf: saved.url), bytes); XCTAssertThrowsError(try export.commit())
    }
    func testLogoutAndRuntimeRevocationPreventBlobPublication() async throws {
        for revoke in [false, true] {
            let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
            let api = BlobAPI(), session = AuthenticationSession(client: api, vault: BlobVault(), setupToken: "fixture"); await session.refresh()
            var active = true
            api.stage = { manifest, destination in try self.receipt(manifest, destination, validate: { if !active { throw CancellationError() } }) }
            let export = try await session.authenticatedTrafficBlobExport(try manifest(), destination: .init(newFileURL: root.appendingPathComponent("saved.bin")))
            if revoke { active = false } else { session.logout() }
            XCTAssertThrowsError(try export.commit()); XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
        }
    }
    func testLateBlob200And401CannotPublishOrExpireReplacementSession() async throws {
        for status in [200, 401] {
            let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
            let api = BlobAPI(), session = AuthenticationSession(client: api, vault: BlobVault(), setupToken: "fixture"); await session.refresh()
            var pending: CheckedContinuation<EvidenceExportReceipt, any Error>?
            api.stage = { _, _ in try await withCheckedThrowingContinuation { pending = $0 } }
            let destination = try EvidenceExportDestination(newFileURL: root.appendingPathComponent("saved.bin"))
            let job = Task { try await session.authenticatedTrafficBlobExport(try manifest(), destination: destination) }
            while pending == nil { await Task.yield() }
            session.logout(); await session.login(password: "fixture", agreed: true)
            let value = status == 200 ? try receipt(manifest(), destination) : EvidenceExportReceipt(response: .init(result: .init(status: 401, byteCount: 0, sha256: ""), file: nil))
            pending?.resume(returning: value)
            do { _ = try await job.value; XCTFail("Stale blob result") } catch { XCTAssertTrue(error is CancellationError) }
            XCTAssertEqual(session.phase, .authenticated); XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
        }
    }
    func testCancelledLateBlobSuccessDiscardsPrivateStaging() async throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let api = BlobAPI(), session = AuthenticationSession(client: api, vault: BlobVault(), setupToken: "fixture"); await session.refresh()
        var pending: CheckedContinuation<EvidenceExportReceipt, any Error>?
        api.stage = { _, _ in try await withCheckedThrowingContinuation { pending = $0 } }
        let destination = try EvidenceExportDestination(newFileURL: root.appendingPathComponent("saved.bin"))
        let job = Task { try await session.authenticatedTrafficBlobExport(try manifest(), destination: destination) }
        while pending == nil { await Task.yield() }
        job.cancel(); pending?.resume(returning: try receipt(manifest(), destination))
        do { _ = try await job.value; XCTFail("Cancelled late success") } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(session.phase, .authenticated); XCTAssertEqual(api.bearers.count, 1)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
    }
    func testCurrentBlob401ExpiresAuthButRevokedVM401DoesNot() async throws {
        for revoked in [false, true] {
            let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
            let api = BlobAPI(), vault = BlobVault(), session = AuthenticationSession(client: api, vault: vault, setupToken: "fixture"); await session.refresh(); vault.fail = true
            api.stage = { _, _ in EvidenceExportReceipt(response: .init(result: .init(status: 401, byteCount: 0, sha256: ""), file: nil), validate: { if revoked { throw CancellationError() } }) }
            do { _ = try await session.authenticatedTrafficBlobExport(try manifest(), destination: .init(newFileURL: root.appendingPathComponent("saved.bin"))); XCTFail("401") } catch { }
            XCTAssertEqual(session.phase, revoked ? .authenticated : .needsLogin)
            XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
        }
    }
    func testUnauthenticatedPrecancelAndStoppedVMRefuseBlobTransfer() async throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let api = BlobAPI(), session = AuthenticationSession(client: api, vault: BlobVault(), setupToken: "fixture")
        let destination = try EvidenceExportDestination(newFileURL: root.appendingPathComponent("saved.bin"))
        do { _ = try await session.authenticatedTrafficBlobExport(try manifest(), destination: destination); XCTFail("Unauthenticated") } catch { }
        await session.refresh()
        let task = Task { try await session.authenticatedTrafficBlobExport(try manifest(), destination: destination) }; task.cancel()
        do { _ = try await task.value; XCTFail("Precancel") } catch { XCTAssertTrue(error is CancellationError) }
        let provisioning = try GuestProvisioning(transportToken: String(repeating: "a", count: 64), setupToken: String(repeating: "b", count: 64))
        let client: any BackendTrafficBlobDownloadTransport = BackendJSONClient(runtime: VMController(), provisioning: provisioning)
        do { _ = try await client.stageTrafficBlob(try manifest(), destination: destination, bearer: "fixture.jwt"); XCTFail("Stopped VM") } catch { }
        XCTAssertTrue(api.bearers.isEmpty); XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
    }
}
