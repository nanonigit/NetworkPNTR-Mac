import ArtexCore
import Foundation
import XCTest
@testable import ArtexCore
@testable import VMProbe

@MainActor private final class SourceBlobVault: SessionVault {
    func load() throws -> String? { "fixture.jwt" }
    func save(_ token: String) throws { }
    func remove() throws { }
}
@MainActor private final class SourceBlobAPI: BackendJSONTransport, BackendTrafficBlobDownloadTransport {
    var active = true, corrupt = false
    var stages = 0
    var bytes: Data { try! CapturedProbeContract.bytes(4, side: .response) }
    func send(method: String, path: String, body: Data?, bearer: String?) async throws -> BackendHTTPResponse {
        let object: Any
        if path == "/api/auth/status" { object = ["initialized": true, "setup_token_required": false] }
        else if path == "/api/auth/login" { object = ["token": "fixture.jwt"] }
        else if path == "/api/llm/profiles" { object = ["profiles": []] }
        else {
            let items = URLComponents(string: path)?.queryItems ?? []
            guard items.first(where: { $0.name == "id" })?.value == "traffic-4", items.first(where: { $0.name == "side" })?.value == "response" else { return .init(status: 404, body: Data()) }
            object = ["id": "traffic-4", "side": "response", "size": bytes.count, "hash": corrupt ? String(repeating: "a", count: 64) : ArtifactIntegrity.sha256(bytes)]
        }
        return .init(status: 200, body: try JSONSerialization.data(withJSONObject: object))
    }
    func stageTrafficBlob(_ manifest: TrafficBlobDownload, destination: EvidenceExportDestination, bearer: String) async throws -> EvidenceExportReceipt {
        stages += 1; XCTAssertEqual(bearer, "fixture.jwt")
        guard manifest.expectedSize == bytes.count else { throw BackendAPIError.invalidResponse }
        let writer = try EvidenceExportWriter(destination: destination, request: manifest)
        var offset = 0
        while offset < bytes.count { let end = min(offset + 65536, bytes.count); try writer.append(bytes.subdata(in: offset..<end)); offset = end }
        let result = BackendDownloadResult(status: 200, byteCount: Int64(bytes.count), sha256: ArtifactIntegrity.sha256(bytes))
        return EvidenceExportReceipt(response: .init(result: result, file: try writer.finish(response: result)), validate: { [weak self] in if self?.active != true { throw CancellationError() } })
    }
    func records() throws -> [CapturedTrafficExchange] {
        try (0..<29).map { index in
            try BackendJSONCoding.decode(CapturedTrafficExchange.self, from: JSONSerialization.data(withJSONObject: ["id": "traffic-"+String(index), "ts": "raw", "host": "127.0.0.1", "url": CapturedProbeContract.prefix + String(format: "%02d", index), "method": "GET", "content_type": "application/octet-stream", "status": 200, "resp_len": index == 4 ? bytes.count : 0]))
        }
    }
}

@MainActor final class SourceBlobProbeTests: XCTestCase {
    func testManagedCandidateRequiresKnownCapabilitiesAndMatchingBinaryMetadata() throws {
        let hash = String(repeating: "a", count: 64)
        let original: [String: Any] = ["architecture": "arm64", "sourceCommit": "e75ae371ad777ffd1eecdd28d2781a6519b05591", "bootMode": "rootDisk", "cpuCount": 1, "networkDevices": 0, "hostShares": 0, "backendSHA256": hash, "managedCapabilities": ["traffic-blob-metadata-v1", "regular-source-blob-stream-v1"], "managedBackend": ["binarySHA256": hash, "buildVersion": "artex-mac-e75ae371-blob1"]]
        try SourceBlobProbe.validateCandidate(original)
        for key in ["architecture", "sourceCommit", "bootMode", "cpuCount", "networkDevices", "hostShares", "backendSHA256", "managedCapabilities", "managedBackend"] {
            var missing = original; missing.removeValue(forKey: key)
            XCTAssertThrowsError(try SourceBlobProbe.validateCandidate(missing), key)
        }
    }
    func testIndependentOriginalManifestRejectsWrongBindingSideSizeAndHash() throws {
        let api = SourceBlobAPI(), row = try api.records()[4]
        let valid = try TrafficBlobDownload(trafficID: row.id, side: .response, expectedSize: Int64(api.bytes.count), expectedSHA256: ArtifactIntegrity.sha256(api.bytes))
        try SourceBlobProbe.validateManifest(valid, row: row)
        for mode in 0..<4 {
            let wrong = try TrafficBlobDownload(trafficID: mode == 0 ? "other" : row.id, side: mode == 1 ? .request : .response, expectedSize: mode == 2 ? valid.expectedSize+1 : valid.expectedSize, expectedSHA256: mode == 3 ? String(repeating: "a", count: 64) : valid.expectedSHA256)
            XCTAssertThrowsError(try SourceBlobProbe.validateManifest(wrong, row: row))
        }
    }
    func testFullProofRequiresActualSavedBytesStopRejectionAndRebootRead() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("artex-source-blob-test-"+UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false); defer { try? FileManager.default.removeItem(at: directory) }
        let api = SourceBlobAPI(), session = AuthenticationSession(client: api, vault: SourceBlobVault(), setupToken: "fixture"); await session.refresh()
        let result = try await SourceBlobProbe.exercise(session: session, api: api, records: api.records(), directory: directory)
        XCTAssertThrowsError(try result.requireComplete())
        api.active = false; try result.afterVMStop(); XCTAssertThrowsError(try result.requireComplete())
        api.active = true; try await result.verifyReboot(session: session, api: api)
        try result.requireComplete(); XCTAssertEqual(api.stages, 4)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted(), ["source-original-4-response-reboot.bin", "source-original-4-response.bin"])
        XCTAssertEqual(result.report["bytes"] as? Int, 262401)
    }
    func testAuthenticationLossCannotCountAsVMStopEvenAfterRelogin() async throws {
        for relogin in [false, true] {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("artex-source-auth-"+UUID().uuidString)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
            defer { try? FileManager.default.removeItem(at: directory) }
            let api = SourceBlobAPI(), session = AuthenticationSession(client: api, vault: SourceBlobVault(), setupToken: "fixture")
            await session.refresh()
            let result = try await SourceBlobProbe.exercise(session: session, api: api, records: api.records(), directory: directory)
            session.logout()
            if relogin { await session.login(password: "fixture", agreed: true); XCTAssertEqual(session.phase, .authenticated) }
            XCTAssertTrue(api.active)
            XCTAssertThrowsError(try result.afterVMStop(), "Authentication cancellation is not a VM stop")
            XCTAssertEqual(result.report["vmStopPublicationRejected"] as? Bool, false)
            try result.discardPending()
        }
    }
    func testProofRetainsOriginalSessionUntilStopAndRejectsCanceledTask() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("artex-source-retention-"+UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let api = SourceBlobAPI()
        var session: AuthenticationSession? = AuthenticationSession(client: api, vault: SourceBlobVault(), setupToken: "fixture")
        await session!.refresh()
        weak var original = session
        let result = try await SourceBlobProbe.exercise(session: session!, api: api, records: api.records(), directory: directory)
        session = nil
        XCTAssertNotNil(original)
        api.active = false
        let canceled = Task { @MainActor in
            withUnsafeCurrentTask { $0?.cancel() }
            XCTAssertThrowsError(try result.afterVMStop())
            XCTAssertEqual(result.report["vmStopPublicationRejected"] as? Bool, false)
        }
        try await canceled.value
        try result.afterVMStop()
        XCTAssertEqual(result.report["vmStopPublicationRejected"] as? Bool, true)
    }
    func testCapturedPreflightSeparatesLegacyAndManagedBackends() throws {
        let hash = String(repeating: "a", count: 64)
        var managed: [String: Any] = ["architecture": "arm64", "sourceCommit": "e75ae371ad777ffd1eecdd28d2781a6519b05591", "bootMode": "rootDisk", "cpuCount": 1, "networkDevices": 0, "hostShares": 0, "captureListener": "127.0.0.1:8788", "backendSHA256": hash, "managedCapabilities": ["traffic-blob-metadata-v1", "regular-source-blob-stream-v1"], "managedBackend": ["binarySHA256": hash, "buildVersion": "artex-mac-e75ae371-blob1"]]
        try CapturedProbe.validateArtifactMetadata(managed, sourceBlobs: true)
        XCTAssertThrowsError(try CapturedProbe.validateArtifactMetadata(managed, sourceBlobs: false))
        managed["backendSHA256"] = "0ebad83ddda276b03b415d64ce30af44e7a587860f3b660c12563462a0ac5e80"
        try CapturedProbe.validateArtifactMetadata(managed, sourceBlobs: false)
        XCTAssertThrowsError(try CapturedProbe.validateArtifactMetadata(managed, sourceBlobs: true))
        managed["captureListener"] = "0.0.0.0:8788"
        XCTAssertThrowsError(try CapturedProbe.validateArtifactMetadata(managed, sourceBlobs: false))
    }
    func testCorruptMetadataCannotCreateAnExportOrSuccessfulProof() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("artex-source-blob-reject-"+UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false); defer { try? FileManager.default.removeItem(at: directory) }
        let api = SourceBlobAPI(); api.corrupt = true
        let session = AuthenticationSession(client: api, vault: SourceBlobVault(), setupToken: "fixture"); await session.refresh()
        do { _ = try await SourceBlobProbe.exercise(session: session, api: api, records: api.records(), directory: directory); XCTFail("Corrupt metadata") } catch { }
        XCTAssertEqual(api.stages, 0); XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
    }
}
