import ArtexCore
import Foundation
import XCTest
@testable import ArtexMac

@MainActor private final class DiagnosticUploadVault: SessionVault {
    func load() throws -> String? { "fixture.jwt" }
    func save(_ token: String) throws { }
    func remove() throws { }
}
@MainActor private final class DiagnosticUploadAPI: BackendJSONTransport, BackendMultipartTransport {
    var failDownload = false
    var guestFiles: [String: Data] = [:]
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
        if path.hasPrefix("/api/workspace/download?") {
            let query = URLComponents(string: "http://fixture" + path)
            let selected = query?.queryItems?.first(where: { $0.name == "path" })?.value ?? ""
            let name = URL(fileURLWithPath: selected).lastPathComponent
            return BackendHTTPResponse(status: 200, body: failDownload ? Data("wrong".utf8) : (guestFiles[name] ?? Data()))
        }
        if method == "DELETE", path.hasPrefix("/api/workspace/delete?") {
            let query = URLComponents(string: "http://fixture" + path)
            guard query?.queryItems?.first(where: { $0.name == "path" })?.value == "sessions/conv-73/uploads" else { throw BackendAPIError.invalidResponse }
            cleanup.append("files"); guestFiles.removeAll(); return try json(["ok": true])
        }
        if method == "DELETE", path == "/api/conversations/73" { cleanup.append("conversation"); return try json(["deleted":73]) }
        throw BackendAPIError.invalidResponse
    }
    func upload(conversationID: Int64, files: [URL], bearer: String) async throws -> BackendHTTPResponse {
        let names = ["fixture.bin", "empty.txt", "fixture-1.bin"]
        var attachments: [[String: Any]] = []
        for (name,url) in zip(names, files) {
            let bytes = try Data(contentsOf: url); guestFiles[name] = bytes
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
}
