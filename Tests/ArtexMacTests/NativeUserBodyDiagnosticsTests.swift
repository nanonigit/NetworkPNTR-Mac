#if DEBUG
import Foundation
import XCTest
@testable import ArtexCore
@testable import ArtexMac

final class NativeUserBodyDiagnosticsTests: XCTestCase {
    @MainActor final class Client: BackendJSONTransport, ChatAttachmentUploading {
        var ids: [Int64] = [], deleted: [Int64] = []
        var bodies: [Int64: [String: Any]] = [:]
        var uploads = 0, failUploadAt = 0
        func send(method: String, path: String, body: Data?, bearer: String?) async throws -> BackendHTTPResponse {
            var object: [String: Any] = [:]
            if path == "/api/conversations" {
                if method == "POST" {
                    let id = Int64(ids.count + 11); ids.append(id)
                    let input = try JSONSerialization.jsonObject(with: XCTUnwrap(body)) as! [String: Any]
                    object = ["id": id, "agent_key": "auto", "title": input["title"] as Any, "created_at": "fixture", "updated_at": "fixture"]
                } else { object = ["conversations": []] }
            } else {
                let parts = path.split(separator: "/")
                let id = try XCTUnwrap(Int64(parts[2]))
                if method == "DELETE" { deleted.append(id); object = ["deleted": id] }
                else if method == "POST" {
                    bodies[id] = try JSONSerialization.jsonObject(with: XCTUnwrap(body)) as? [String: Any]
                    object = ["status": "accepted"]
                } else if parts.count > 4 {
                    let request = try XCTUnwrap(bodies[id])
                    let text = request["message"] as? String ?? ""
                    let detail = try JSONSerialization.data(withJSONObject: ["text": text, "attachments": request["attachments"] as Any])
                    object = ["detail": String(decoding: detail, as: UTF8.self)]
                } else {
                    object = ["items": [["seq": 1, "worker": "auto", "ts": "fixture", "kind": "user", "summary": bodies[id]?["message"] as? String ?? ""]], "cursor": 1, "running": false, "has_more": false]
                }
            }
            return BackendHTTPResponse(status: 200, body: try JSONSerialization.data(withJSONObject: object))
        }
        func uploadAttachments(conversationID: Int64, files: [URL], progress: BackendUploadProgressHandler?) async throws -> [ChatAttachment] {
            uploads += 1
            if uploads == failUploadAt { throw ChatUploadBodyError.readFailure }
            return try files.map { try ChatAttachment(name: $0.lastPathComponent, path: "uploads/" + $0.lastPathComponent, size: Int64(Data(contentsOf: $0).count)) }
        }
    }
    @MainActor func testOwnedSeedLoadsPersistedBodiesAndExplicitCleanupDeletesOnlyOwnedIDs() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let client = Client()
        let ids = try await NativeUserBodyDiagnostics.seed(client: client, directory: root)
        XCTAssertEqual(ids, [11, 12, 13]); XCTAssertTrue(client.deleted.isEmpty)
        let report = try JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent("user-body-contract-vm.json"))) as! [String: Any]
        let cases = try XCTUnwrap(report["cases"] as? [[String: Any]])
        XCTAssertEqual(cases.count, 3)
        XCTAssertEqual((cases[1]["text"] as? String), "")
        XCTAssertEqual((cases[2]["attachments"] as? [[String: Any]])?.count, 2)
        try await NativeUserBodyDiagnostics.cleanup(client: client, ids: ids)
        XCTAssertEqual(client.deleted, ids)
    }
    @MainActor func testSeedFailureCleansEveryAlreadyCreatedConversation() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let client = Client(); client.failUploadAt = 2
        do { _ = try await NativeUserBodyDiagnostics.seed(client: client, directory: root); XCTFail("Expected fixture failure") } catch {}
        XCTAssertEqual(client.ids, [11, 12]); XCTAssertEqual(client.deleted, [11, 12])
    }
}
#endif
