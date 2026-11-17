import Foundation
import XCTest
@testable import NetworkPNTRCore
@testable import NetworkPNTRMac

@MainActor private final class HandoffVault: SessionVault {
    func load() throws -> String? { "fixture.jwt" }
    func save(_ token: String) throws { }
    func remove() throws { }
}
@MainActor private final class HandoffAPI: BackendJSONTransport, BackendMultipartTransport {
    var acceptsSend = false
    var next: Int64 = 30
    var ids: [Int64] = []
    var files: [Int64:[(String,Data)]] = [:]
    var removed: [Int64] = []
    private func json(_ object: Any, status: Int = 200) throws -> BackendHTTPResponse {
        BackendHTTPResponse(status:status,body:try JSONSerialization.data(withJSONObject:object))
    }
    func send(method: String, path: String, body: Data?, bearer: String?) async throws -> BackendHTTPResponse {
        if path == "/api/auth/status" { return try json(["initialized":true,"setup_token_required":false]) }
        if path == "/api/llm/profiles" { return try json(["profiles":[]]) }
        if path == "/api/conversations" {
            if method == "POST" { next += 1; ids.append(next); return try json(conversation(next)) }
            return try json(["conversations":ids.map { conversation($0) }])
        }
        if path.hasPrefix("/api/workspace/") {
            let value = URLComponents(string:"http://fixture" + path)?.queryItems?.first?.value ?? ""
            let parts = value.split(separator:"/")
            guard parts.count >= 3, let id = Int64(parts[1].dropFirst(5)) else { throw BackendAPIError.invalidResponse }
            if path.hasPrefix("/api/workspace/list?") { return try json(["entries":(files[id] ?? []).map { ["name":$0.0,"size":$0.1.count] as [String:Any] }]) }
            if path.hasPrefix("/api/workspace/download?") {
                let name = String(parts.last!)
                let bytes = files[id]?.first { $0.0.utf8.elementsEqual(name.utf8) }?.1 ?? Data()
                return BackendHTTPResponse(status:200,body:bytes)
            }
            if method == "DELETE" { files.removeValue(forKey:id); return try json(["ok":true]) }
        }
        if path.hasSuffix("/messages") || path.contains("/messages?") {
            if method == "POST" { return try json(["status":acceptsSend ? "accepted":"unavailable"],status:acceptsSend ? 202:503) }
            return try json(["items":[],"cursor":0,"running":false,"hasMore":false])
        }
        if method == "DELETE", let id = Int64(path.split(separator:"/").last ?? "") {
            ids.removeAll { $0 == id }; removed.append(id); return try json(["deleted":id])
        }
        throw BackendAPIError.invalidResponse
    }
    func upload(conversationID: Int64, files selected: [URL], bearer: String, progress: BackendUploadProgressHandler?) async throws -> BackendHTTPResponse {
        let records = try selected.map { ($0.lastPathComponent,try Data(contentsOf:$0)) }
        files[conversationID] = records
        return try json(["attachments":records.map { ["name":$0.0,"path":"uploads/"+$0.0,"size":$0.1.count,"abs":"/guest/private"] as [String:Any] }])
    }
    private func conversation(_ id: Int64) -> [String:Any] { ["id":id,"agent_key":"auto","title":"fixture","created_at":"fixture","updated_at":"fixture"] }
}
final class NativeAttachmentHandoffDiagnosticsTests: XCTestCase {
    @MainActor func testTypedHandoffFixtureConfirmsFailuresFilePreservationAndOwnedCleanup() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("artex-handoff-test-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:directory) }
        let api = HandoffAPI(), session = AuthenticationSession(client:api,vault:HandoffVault(),setupToken:"fixture")
        await session.refresh()
        try await NativeAttachmentHandoffDiagnostics.run(session:session,directory:directory)
        XCTAssertTrue(api.files.isEmpty); XCTAssertEqual(Set(api.removed),[31,32])
        let report = try JSONSerialization.jsonObject(with:Data(contentsOf:directory.appendingPathComponent("attachment-handoff-vm.json"))) as! [String:Any]
        XCTAssertEqual(report["failed_send_statuses"] as? [Int],[503,503])
        XCTAssertEqual(report["owned_files_and_conversation_cleaned"] as? Bool,true)
        XCTAssertFalse(FileManager.default.fileExists(atPath:directory.appendingPathComponent("attachment-handoff-selected").path))
    }
    @MainActor func testUnexpectedAcceptedSendCannotProduceSuccessArtifactAndCleansOwnedData() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("artex-handoff-bad-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:directory) }
        let api = HandoffAPI(); api.acceptsSend = true
        let session = AuthenticationSession(client:api,vault:HandoffVault(),setupToken:"fixture")
        await session.refresh()
        do { try await NativeAttachmentHandoffDiagnostics.run(session:session,directory:directory); XCTFail("Unexpected send acceptance") } catch { }
        XCTAssertTrue(api.files.isEmpty); XCTAssertEqual(api.removed,[31])
        XCTAssertFalse(FileManager.default.fileExists(atPath:directory.appendingPathComponent("attachment-handoff-vm.json").path))
    }
}
