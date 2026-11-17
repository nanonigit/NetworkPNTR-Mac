import Foundation
import XCTest
@testable import NetworkPNTRCore

@MainActor private final class AttachmentClientVault: SessionVault {
    var token: String? = "fixture.jwt"
    func load() throws -> String? { token }
    func save(_ token: String) throws { self.token = token }
    func remove() throws { token = nil }
}
@MainActor private final class AttachmentRawAPI: BackendJSONTransport, BackendMultipartTransport {
    var response: BackendHTTPResponse = .init(status: 200, body: Data())
    var uploadCalls = 0
    var bearer: String?
    func send(method: String, path: String, body: Data?, bearer: String?) async throws -> BackendHTTPResponse {
        try ChatTestTransport.response(path == "/api/auth/status" ? ["initialized":true,"setup_token_required":false] : ["profiles":[]])
    }
    func upload(conversationID: Int64, files: [URL], bearer: String, progress: BackendUploadProgressHandler?) async throws -> BackendHTTPResponse {
        uploadCalls += 1; self.bearer = bearer
        return response
    }
}
final class ChatAttachmentUploadClientTests: XCTestCase {
    private let files = [URL(fileURLWithPath: "/synthetic/selected.txt")]
    @MainActor func testTypedCapabilityUsesLiveSessionAndDropsGuestAbsolutePath() async throws {
        let api = AttachmentRawAPI(), vault = AttachmentClientVault()
        let session = AuthenticationSession(client: api, vault: vault, setupToken: "fixture")
        await session.refresh()
        let client: any ChatAttachmentUploading = AuthenticatedBackendClient(session: session)
        api.response = try ChatTestTransport.response(["attachments":[["name":"selected.txt","path":"uploads/selected.txt","size":0,"abs":"/guest/private/path"]]])
        let attachments = try await client.uploadAttachments(conversationID: 7, files: files)
        XCTAssertEqual(attachments, [try ChatAttachment(name:"selected.txt",path:"uploads/selected.txt",size:0)])
        XCTAssertEqual(api.bearer, "fixture.jwt")
        let encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(attachments[0])) as! [String:Any]
        XCTAssertNil(encoded["abs"])
    }
    @MainActor func testInvalidInputAndUnauthenticatedStateNeverReachUpload() async throws {
        let api = AttachmentRawAPI(), session = AuthenticationSession(client: api, vault: AttachmentClientVault(), setupToken: "fixture")
        let client: any ChatAttachmentUploading = AuthenticatedBackendClient(session: session)
        do { _ = try await client.uploadAttachments(conversationID: 7, files: files); XCTFail("Unauthenticated") } catch { }
        await session.refresh()
        for id: Int64 in [0,-1] {
            do { _ = try await client.uploadAttachments(conversationID: id, files: files); XCTFail("Invalid ID") } catch { }
        }
        do { _ = try await client.uploadAttachments(conversationID: 7, files: []); XCTFail("Empty selection") } catch { }
        XCTAssertEqual(api.uploadCalls, 0)
    }
    @MainActor func testMalformedIncompleteAndErrorResponsesCannotReturnMetadata() async throws {
        let api = AttachmentRawAPI(), session = AuthenticationSession(client: api, vault: AttachmentClientVault(), setupToken: "fixture")
        await session.refresh()
        let client: any ChatAttachmentUploading = AuthenticatedBackendClient(session: session)
        for object: [String:Any] in [["attachments":[]], ["unexpected":true], ["attachments":[["name":"a","path":"../a","size":1]]],
                                    ["attachments":[["name":"a","path":"uploads/a","size":1],["name":"b","path":"uploads/b","size":1]]]] {
            api.response = try ChatTestTransport.response(object)
            do { _ = try await client.uploadAttachments(conversationID: 7, files: files); XCTFail("Invalid metadata") } catch { }
        }
        api.response = try ChatTestTransport.response(["error":"private backend body"],status:503)
        do { _ = try await client.uploadAttachments(conversationID: 7, files: files); XCTFail("Backend error") }
        catch { XCTAssertFalse(error.localizedDescription.contains("private backend body")) }
        api.response = try ChatTestTransport.response(["error":"private"],status:401)
        do { _ = try await client.uploadAttachments(conversationID: 7, files: files); XCTFail("Expired auth") } catch { }
        XCTAssertEqual(session.phase, .needsLogin)
    }
}
