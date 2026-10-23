import ArtexCore
import CryptoKit
import Foundation
import XCTest
@testable import ArtexMac

@MainActor private final class DiagnosticUploadVault: SessionVault {
    func load() throws -> String? { "fixture.jwt" }
    func save(_ token: String) throws { }
    func remove() throws { }
}
@MainActor private final class DiagnosticUploadAPI: BackendJSONTransport, BackendMultipartTransport, BackendAttachmentDownloadTransport {
    var failDownload = false
    var failLargeDigest = false
    var digestRequests: [String] = []
    var guestFiles: [String: Data] = [:]
    var guestSizes: [String: Int64] = [:]
    var cleanup: [String] = []
    private func json(_ object: Any) throws -> BackendHTTPResponse {
        BackendHTTPResponse(status: 200, body: try JSONSerialization.data(withJSONObject: object))
    }
    func send(method: String, path: String, body: Data?, bearer: String?) async throws -> BackendHTTPResponse {
        if path == "/api/auth/status" { return try json(["initialized": true, "setup_token_required": false]) }
        if path == "/api/llm/profiles" { return try json(["profiles": []]) }
        if method == "POST", path == "/api/conversations" {
            return try json(["id":73,"agent_key":"auto","title":"fixture","created_at":"fixture","updated_at":"fixture"])
        }
        if path.hasPrefix("/api/workspace/list?") {
            return try json(["entries": guestSizes.map { ["name": $0.key, "size": $0.value] as [String: Any] }])
        }
        if path.hasPrefix("/api/workspace/download?") {
            let query = URLComponents(string: "http://fixture" + path)
            let selected = query?.queryItems?.first(where: { $0.name == "path" })?.value ?? ""
            let name = URL(fileURLWithPath: selected).lastPathComponent
            return BackendHTTPResponse(status: 200, body: failDownload ? Data("wrong".utf8) : (guestFiles[name] ?? Data()))
        }
        if method == "DELETE", path.hasPrefix("/api/workspace/delete?") {
            let query = URLComponents(string: "http://fixture" + path)
            guard query?.queryItems?.first(where: { $0.name == "path" })?.value == "sessions/conv-73/uploads" else { throw BackendAPIError.invalidResponse }
            cleanup.append("files"); guestFiles.removeAll(); guestSizes.removeAll(); return try json(["ok": true])
        }
        if method == "DELETE", path == "/api/conversations/73" { cleanup.append("conversation"); return try json(["deleted":73]) }
        throw BackendAPIError.invalidResponse
    }
    func downloadDigest(_ attachment: ChatAttachmentDownload, bearer: String) async throws -> BackendDownloadResult {
        digestRequests.append(attachment.name)
        var hash = SHA256(), remaining = attachment.expectedSize
        while remaining > 0 {
            let count = Int(min(remaining, 65536)); hash.update(data: Data(repeating: 0, count: count)); remaining -= Int64(count)
        }
        let digest = hash.finalize().map { String(format: "%02x", $0) }.joined()
        return BackendDownloadResult(status: 200, byteCount: attachment.expectedSize, sha256: failLargeDigest ? "wrong" : digest)
    }
    func upload(conversationID: Int64, files: [URL], bearer: String, progress: BackendUploadProgressHandler? = nil) async throws -> BackendHTTPResponse {
        if files.count == 1, files[0].lastPathComponent == "limit.bin" {
            _ = try ChatMultipartPlan(files: files)
            let size = (try FileManager.default.attributesOfItem(atPath: files[0].path)[.size] as! NSNumber).int64Value
            guestSizes["limit.bin"] = size
            return try json(["attachments": [["name":"limit.bin", "path":"uploads/limit.bin", "size":size]]])
        }
        let names = ["fixture.bin", "empty.txt", "fixture-1.bin"]
        var attachments: [[String: Any]] = []
        for (name,url) in zip(names, files) {
            let bytes = try Data(contentsOf: url); guestFiles[name] = bytes; guestSizes[name] = Int64(bytes.count)
            attachments.append(["name":name,"path":"uploads/" + name,"size":bytes.count])
        }
        return try json(["attachments": attachments])
    }
}
final class NativeUploadDiagnosticsTests: XCTestCase {
    @MainActor func testFixtureCleansOwnedGuestFilesBeforeConversationOnSuccessAndDownloadFailure() async throws {
        for fail in [false,true] {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent("artex-native-upload-test-" + UUID().uuidString)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: root) }
            let api = DiagnosticUploadAPI(); api.failDownload = fail
            let session = AuthenticationSession(client: api, vault: DiagnosticUploadVault(), setupToken: "fixture")
            await session.refresh()
            do {
                try await NativeUploadDiagnostics.run(session: session, directory: root)
                XCTAssertFalse(fail, "Injected content failure was not detected")
            } catch { XCTAssertTrue(fail, "Unexpected fixture failure") }
            XCTAssertTrue(api.guestFiles.isEmpty)
            XCTAssertEqual(api.cleanup, ["files","conversation"])
            XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("upload-selected-fixtures").path))
            XCTAssertEqual(FileManager.default.fileExists(atPath: root.appendingPathComponent("upload-contract-vm.json").path), !fail)
        }
    }
    @MainActor func testLargeDigestMismatchCannotPublishSuccessAndStillCleansOwnedData() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("artex-native-upload-hash-test-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let api = DiagnosticUploadAPI(); api.failLargeDigest = true
        let session = AuthenticationSession(client: api, vault: DiagnosticUploadVault(), setupToken: "fixture")
        await session.refresh()
        do { try await NativeUploadDiagnostics.run(session: session, directory: root, includeLimit: true); XCTFail("Mismatched full hash") } catch { }
        XCTAssertEqual(api.digestRequests, ["limit.bin"])
        XCTAssertEqual(api.cleanup, ["files", "conversation"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("upload-contract-vm.json").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("upload-selected-fixtures").path))
    }
    @MainActor func testOptionalLimitFixtureCountsFramingAndPreservesOwnedCleanup() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("artex-native-upload-limit-test-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let api = DiagnosticUploadAPI()
        let session = AuthenticationSession(client: api, vault: DiagnosticUploadVault(), setupToken: "fixture")
        await session.refresh()
        try await NativeUploadDiagnostics.run(session: session, directory: root, includeLimit: true)
        let report = try JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent("upload-contract-vm.json"))) as! [String: Any]
        let limit = try XCTUnwrap(report["limit"] as? [String: Any])
        XCTAssertEqual((limit["body_bytes"] as? NSNumber)?.int64Value, 128 * 1024 * 1024)
        XCTAssertEqual((limit["file_size"] as? NSNumber)?.int64Value, (limit["persisted_size"] as? NSNumber)?.int64Value)
        XCTAssertEqual(limit["over_limit_rejected"] as? Bool, true)
        XCTAssertEqual(limit["duplicate_after_rejection"] as? Bool, false)
        XCTAssertEqual(api.digestRequests, ["limit.bin"])
        XCTAssertEqual((limit["downloaded_size"] as? NSNumber)?.int64Value, (limit["file_size"] as? NSNumber)?.int64Value)
        XCTAssertEqual((limit["sha256"] as? String)?.count, 64)
        XCTAssertEqual(limit["full_content_hash_verified"] as? Bool, true)
        XCTAssertTrue(api.guestFiles.isEmpty); XCTAssertTrue(api.guestSizes.isEmpty)
        XCTAssertEqual(api.cleanup, ["files", "conversation"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("upload-selected-fixtures").path))
    }

}
