import Foundation
import XCTest
@testable import ArtexCore

@MainActor private final class StagingVault: SessionVault {
    var token: String? = "old.jwt"
    func load() throws -> String? { token }
    func save(_ token: String) throws { self.token = token }
    func remove() throws { token = nil }
}
@MainActor private final class StagingAPI: BackendJSONTransport, BackendStagingMultipartTransport {
    var response = BackendHTTPResponse(status: 200, body: Data())
    var calls: [(UUID, [URL], String)] = []
    var handler: (() async throws -> BackendHTTPResponse)?
    var progress: BackendUploadProgressHandler?
    func send(method: String, path: String, body: Data?, bearer: String?) async throws -> BackendHTTPResponse {
        try ChatTestTransport.response(path == "/api/auth/status" ? ["initialized":true,"setup_token_required":false] : path == "/api/auth/login" ? ["token":"new.jwt"] : ["profiles":[]])
    }
    func uploadStaging(draftID: UUID, files: [URL], bearer: String, progress: BackendUploadProgressHandler?) async throws -> BackendHTTPResponse {
        calls.append((draftID, files, bearer)); self.progress = progress
        progress?(.init(sentBodyBytes: 1, totalBodyBytes: 10))
        if let handler { return try await handler() }
        return response
    }
}

private final class StagingObservedProgress: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var received: Int { lock.lock(); defer { lock.unlock() }; return count }
    func record(_ value: BackendUploadProgress) { lock.lock(); defer { lock.unlock() }; count += 1 }
}

final class TaskStagingUploadTests: XCTestCase {
    private let draft = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
    private let files = [URL(fileURLWithPath: "/synthetic/selected.txt")]
    private func raw(name: String = "report-1.txt", path: String? = nil, absolute: String? = nil, size: Int64 = 0) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["attachments":[["name":name,"path":path ?? "uploads/" + name,"size":size,"abs":absolute ?? "/state/app/data/drafts/\(draft.uuidString.lowercased())/uploads/" + name]]])
    }
    func testFiniteStagingHeaderAndExistingSessionRoute() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data().write(to: file); defer { try? FileManager.default.removeItem(at: file) }
        let plan = try ChatMultipartPlan(files:[file],boundary:"fixture")
        let header = String(decoding: try BackendMultipartRequest.stagingHeader(draftID:draft,plan:plan,bearer:"safe.jwt"),as:UTF8.self)
        XCTAssertTrue(header.hasPrefix("POST /api/chat/upload?scope=staging&id=aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee HTTP/1.1\r\n"))
        XCTAssertTrue(header.contains("Authorization: Bearer safe.jwt\r\n")); XCTAssertTrue(header.contains("Content-Length: \(plan.contentLength)\r\n"))
        XCTAssertTrue(String(decoding:try BackendMultipartRequest.header(conversationID:7,plan:plan,bearer:"safe.jwt"),as:UTF8.self).hasPrefix("POST /api/chat/upload?scope=session&id=conv-7 HTTP/1.1\r\n"))
        for token in ["", "x\r\nHost: bad", String(repeating:"a",count:8193), "日本語"] {
            XCTAssertThrowsError(try BackendMultipartRequest.stagingHeader(draftID:draft,plan:plan,bearer:token))
        }
    }
    @MainActor func testUsesLiveBearerAndPreservesValidatedGuestUnicodePaths() async throws {
        let api = StagingAPI(), session = AuthenticationSession(client:api,vault:StagingVault(),setupToken:"fixture")
        await session.refresh()
        let client: any TaskStagingUploading = AuthenticatedBackendClient(session:session)
        for name in ["report-1.txt", "\u{FEFF}e\u{301}日本.txt", "é日本.txt"] {
            api.response = .init(status:200,body:try raw(name:name))
            let result = try await client.uploadTaskStaging(draftID:draft,files:files,progress:nil)
            XCTAssertEqual(result.count,1); XCTAssertTrue(result[0].name.utf8.elementsEqual(name.utf8))
            XCTAssertTrue(result[0].absolutePath.utf8.elementsEqual(("/state/app/data/drafts/" + draft.uuidString.lowercased() + "/uploads/" + name).utf8))
            XCTAssertTrue(result[0].path.utf8.elementsEqual(("uploads/"+name).utf8))
        }
        XCTAssertEqual(api.calls.count,3); XCTAssertTrue(api.calls.allSatisfy { $0.0 == draft && $0.1 == files && $0.2 == "old.jwt" })
    }
    @MainActor func testRejectsForeignPathsMalformedPartialDuplicateAndUnconfirmedReplies() async throws {
        let api = StagingAPI(), session = AuthenticationSession(client:api,vault:StagingVault(),setupToken:"fixture")
        await session.refresh(); let client = AuthenticatedBackendClient(session:session)
        let valid = try JSONSerialization.jsonObject(with: raw()) as! [String:Any]
        let item = (valid["attachments"] as! [[String:Any]])[0]
        var duplicate = valid; duplicate["attachments"] = [item,item]
        for data in [try raw(absolute:"/Users/private/report-1.txt"), try raw(absolute:"/state/app/data/drafts/other/uploads/report-1.txt"),
                     try raw(path:"uploads/../report-1.txt"),try raw(name:"bad\nname"), try raw(size:-1), try raw(size:ChatMultipartPlan.maximumBytes+1),
                     Data(#"{"attachments":[]}"#.utf8),Data(#"{"attachments":[{"name":"a","path":"uploads/a","size":0}]}"#.utf8),
                     try JSONSerialization.data(withJSONObject:duplicate),Data("{}".utf8),Data(repeating:32,count:4*1024*1024+1)] {
            api.response = .init(status:200,body:data)
            do { _ = try await client.uploadTaskStaging(draftID:draft,files:files,progress:nil); XCTFail("Invalid staging accepted") } catch { }
        }
        for status in [201,202,400,503] {
            api.response = .init(status:status,body:Data("private backend failure".utf8))
            do { _ = try await client.uploadTaskStaging(draftID:draft,files:files,progress:nil); XCTFail("Unconfirmed response accepted") }
            catch { XCTAssertFalse(error.localizedDescription.contains("private backend failure")) }
        }
        api.response = .init(status:200,body:try raw())
        do { _ = try await client.uploadTaskStaging(draftID:draft,files:files+files,progress:nil); XCTFail("Partial upload accepted") } catch { }
    }
    @MainActor func testAuthEmptyAndPreCancelledNeverDispatchAndUnauthorizedExpires() async throws {
        let api = StagingAPI(), session = AuthenticationSession(client:api,vault:StagingVault(),setupToken:"fixture")
        let client = AuthenticatedBackendClient(session:session)
        do { _ = try await client.uploadTaskStaging(draftID:draft,files:files,progress:nil); XCTFail("Unauthenticated") } catch { }
        await session.refresh()
        do { _ = try await client.uploadTaskStaging(draftID:draft,files:[],progress:nil); XCTFail("Empty selection") } catch { }
        let pending = Task { @MainActor in try await client.uploadTaskStaging(draftID:self.draft,files:self.files,progress:nil) }; pending.cancel()
        do { _ = try await pending.value; XCTFail("Pre-cancelled") } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertTrue(api.calls.isEmpty)
        api.response = .init(status:401,body:Data())
        do { _ = try await client.uploadTaskStaging(draftID:draft,files:files,progress:nil); XCTFail("Unauthorized") } catch { }
        XCTAssertEqual(session.phase,.needsLogin); XCTAssertEqual(api.calls.count,1)
    }
    @MainActor func testLateReplyAndProgressCannotCrossLoginRevision() async throws {
        let api = StagingAPI(), vault = StagingVault(), session = AuthenticationSession(client:api,vault:vault,setupToken:"fixture")
        await session.refresh(); let client = AuthenticatedBackendClient(session:session)
        var reply: CheckedContinuation<BackendHTTPResponse,Error>?
        api.handler = { try await withCheckedThrowingContinuation { reply = $0 } }
        let observed = StagingObservedProgress()
        let pending = Task { @MainActor in try await client.uploadTaskStaging(draftID:self.draft,files:self.files,progress:{ observed.record($0) }) }
        while reply == nil { await Task.yield() }
        XCTAssertEqual(observed.received,1)
        session.logout(); await session.login(password:"fixture",agreed:true)
        api.progress?(.init(sentBodyBytes:2,totalBodyBytes:10)); XCTAssertEqual(observed.received,1)
        reply?.resume(returning:.init(status:401,body:Data()))
        do { _ = try await pending.value; XCTFail("Old reply accepted") } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(session.phase,.authenticated); XCTAssertEqual(vault.token,"new.jwt"); XCTAssertEqual(api.calls.count,1)
        api.handler = nil; api.response = .init(status:200,body:try raw())
        _ = try await client.uploadTaskStaging(draftID:draft,files:files,progress:nil)
        XCTAssertEqual(api.calls.last?.2,"new.jwt")
    }
    @MainActor func testByteDistinctNamesAndAggregateLimit() async throws {
        let api = StagingAPI(), session = AuthenticationSession(client:api,vault:StagingVault(),setupToken:"fixture")
        await session.refresh(); let client = AuthenticatedBackendClient(session:session)
        var items: [[String:Any]] = []
        for name in ["é.txt", "e\u{301}.txt"] {
            items.append((try JSONSerialization.jsonObject(with:raw(name:name)) as! [String:Any])["attachments"].flatMap { ($0 as? [[String:Any]])?.first }!)
        }
        api.response = .init(status:200,body:try JSONSerialization.data(withJSONObject:["attachments":items]))
        let result = try await client.uploadTaskStaging(draftID:draft,files:files+files,progress:nil)
        XCTAssertEqual(result.count,2); XCTAssertNotEqual(result[0].id,result[1].id)
        for index in items.indices { items[index]["size"] = ChatMultipartPlan.maximumBytes }
        api.response = .init(status:200,body:try JSONSerialization.data(withJSONObject:["attachments":items]))
        do { _ = try await client.uploadTaskStaging(draftID:draft,files:files+files,progress:nil); XCTFail("Impossible aggregate size accepted") } catch { }
    }
    @MainActor func testCancellationClosesProgressAndRejectsLateSuccessWithoutRetry() async throws {
        let api = StagingAPI(), session = AuthenticationSession(client:api,vault:StagingVault(),setupToken:"fixture")
        await session.refresh(); let client = AuthenticatedBackendClient(session:session)
        var reply: CheckedContinuation<BackendHTTPResponse,Error>?
        api.handler = { try await withCheckedThrowingContinuation { reply = $0 } }
        let observed = StagingObservedProgress()
        let pending = Task { @MainActor in try await client.uploadTaskStaging(draftID:self.draft,files:self.files,progress:{ observed.record($0) }) }
        while reply == nil { await Task.yield() }
        pending.cancel(); api.progress?(.init(sentBodyBytes:2,totalBodyBytes:10))
        reply?.resume(returning:.init(status:200,body:try raw()))
        do { _ = try await pending.value; XCTFail("Late success accepted") } catch { XCTAssertTrue(error is CancellationError) }
        api.progress?(.init(sentBodyBytes:3,totalBodyBytes:10))
        XCTAssertEqual(observed.received,1); XCTAssertEqual(api.calls.count,1); XCTAssertEqual(session.phase,.authenticated)
        XCTAssertThrowsError(try JSONDecoder().decode(TaskStagedAttachment.self,from:Data(#"{"name":"a","path":"uploads/a","size":0,"abs":"/x"}"#.utf8)))
    }

    @MainActor func testConcreteClientRejectsInvalidFilesAndNeverStartsVMImplicitly() async throws {
        let runtime = VMController()
        let client = BackendJSONClient(runtime:runtime,provisioning:try GuestProvisioning.generate())
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data("selected file".utf8).write(to:file); defer { try? FileManager.default.removeItem(at:file) }
        for selection in [[], [URL(string:"https://example.invalid/file")!]] {
            do { _ = try await client.uploadStaging(draftID:draft,files:selection,bearer:"safe.jwt",progress:nil); XCTFail("Invalid file accepted") }
            catch { XCTAssertTrue(error is ChatUploadBodyError) }
        }
        do { _ = try await client.uploadStaging(draftID:draft,files:[file],bearer:"bad\r\nheader",progress:nil); XCTFail("Invalid bearer") }
        catch { guard case RuntimeError.integrity("authenticated attachment request") = error else { return XCTFail("Wrong validation boundary") } }
        do { _ = try await client.uploadStaging(draftID:draft,files:[file],bearer:"safe.jwt",progress:nil); XCTFail("Unstarted runtime") }
        catch { guard case RuntimeError.integrity("backend not ready") = error else { return XCTFail("Wrong runtime boundary") } }
        XCTAssertFalse(runtime.hasMachine); XCTAssertEqual(runtime.state,.idle)
    }

}
