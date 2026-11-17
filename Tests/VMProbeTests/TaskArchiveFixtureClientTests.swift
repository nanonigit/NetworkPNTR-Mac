import XCTest
@testable import NetworkPNTRCore
@testable import VMProbe

@MainActor private final class FixtureToolAPI: BackendJSONTransport {
    var calls: [(String,String,Data?)] = []
    var replies: [BackendHTTPResponse] = []
    var cancel = false
    func send(method: String,path: String,body: Data?,bearer: String?) async throws -> BackendHTTPResponse {
        calls.append((method,path,body)); if cancel { withUnsafeCurrentTask{$0?.cancel()} }
        guard !replies.isEmpty else { throw BackendAPIError.invalidResponse }; return replies.removeFirst()
    }
    func append(_ output: String, error: Bool = false, status: Int = 200) throws {
        struct Reply: Encodable { let isError: Bool; let output: String }
        replies.append(.init(status:status,body:try BackendJSONCoding.encode(Reply(isError:error,output:output))))
    }
}
final class TaskArchiveFixtureClientTests: XCTestCase {
    private let fixtureDigest = String(repeating:"a",count:64)
    private var audit: String { #"{"fixture_audit":true,"uid":1000,"counts":{"foreign_tasks":0,"foreign_archives":0,"profiles":0,"activity":0,"conversations":0,"llm_usage":0,"llm_records":0}}"# }
    @MainActor func testOnlyFixedGuestToolRouteAndTypedAuditProof() async throws {
        let api = FixtureToolAPI(); try api.append(audit)
        let control = try TaskArchiveFixtureClient(client:api); try await control.verifyNoAgentActivity()
        XCTAssertEqual(api.calls.count,1); XCTAssertEqual(api.calls[0].0,"POST"); XCTAssertEqual(api.calls[0].1,"/api/tools/custom/test")
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with:XCTUnwrap(api.calls[0].2)) as? [String:Any])
        XCTAssertEqual(object["kind"] as? String,"script"); let exec = try XCTUnwrap(object["exec"] as? [String:Any])
        XCTAssertEqual(exec["timeout_ms"] as? Int,20000)
        let code = try XCTUnwrap(exec["code"] as? String); XCTAssertTrue(code.contains("ARTEX_ARCHIVE_FIXTURE")); XCTAssertFalse(code.contains("/Users/"))
        XCTAssertEqual(control.seedSHA256.count,64); XCTAssertEqual(control.controlSHA256.count,64)
    }
    @MainActor func testPackageProofMustMatchEveryCapturedIdentityField() async throws {
        let valid = "{\"fixture_control\":true,\"operation\":\"hide\",\"archive_id\":7,\"task_id\":7101,\"sha256\":\""+fixtureDigest+"\",\"uid\":1000}"
        let variants = [valid,valid.replacingOccurrences(of:"7101",with:"7102"),valid.replacingOccurrences(of:"\"hide\"",with:"\"repair\""),valid.replacingOccurrences(of:"1000",with:"0"),valid.replacingOccurrences(of:fixtureDigest,with:String(repeating:"b",count:64))]
        for (index,json) in variants.enumerated() {
            let api = FixtureToolAPI(); try api.append(json); let control = try TaskArchiveFixtureClient(client:api)
            do { try await control.setPackageHidden(true,target:.init(archiveID:7,sha256:fixtureDigest)); if index != 0 { XCTFail("foreign package proof accepted") } }
            catch { if index == 0 { throw error } }
        }
    }
    @MainActor func testUnsafeTargetAndMalformedErrorOrNonzeroAuditNeverSucceed() async throws {
        let api = FixtureToolAPI(); let control = try TaskArchiveFixtureClient(client:api)
        for target in [TaskArchiveFixtureTarget(archiveID:0,sha256:fixtureDigest),.init(archiveID:7,sha256:"private code") ] {
            do { try await control.setPackageHidden(true,target:target); XCTFail("invalid target accepted") } catch {}
        }
        XCTAssertTrue(api.calls.isEmpty)
        for output in ["{}",audit.replacingOccurrences(of:"\"activity\":0",with:"\"activity\":1"),audit.replacingOccurrences(of:"1000",with:"0"),"Traceback private"] {
            try api.append(output)
            do { try await control.verifyNoAgentActivity(); XCTFail("invalid audit accepted") } catch {}
        }
        try api.append(audit,error:true); do { try await control.verifyNoAgentActivity(); XCTFail("tool failure accepted") } catch {}
    }
    @MainActor func testSeedRequiresExactFileBytesAndIDsWithoutExecutingHostCode() async throws {
        struct Seed: Encodable { let fixtureSeeded: Bool; let terminalTaskIds: [Int64]; let files: [TaskArchiveFileProof] }
        let proof = TaskArchiveExercise.files.map { TaskArchiveFileProof(path:$0.path,size:Int64($0.data.count),sha256:ArtifactIntegrity.sha256($0.data)) }
        let api = FixtureToolAPI(); let control = try TaskArchiveFixtureClient(client:api)
        for ids: [Int64] in [[7101,7102],[7101,7103]] {
            let data = try BackendJSONCoding.encode(Seed(fixtureSeeded:true,terminalTaskIds:ids,files:proof)); try api.append(String(decoding:data,as:UTF8.self))
            do { try await control.seed(); if ids != [7101,7102] { XCTFail("foreign seeded task accepted") } }
            catch { if ids == [7101,7102] { throw error } }
        }
        XCTAssertEqual(api.calls.count,2)
    }
    @MainActor func testPostDispatchCancellationDoesNotTreatToolProofAsCompletion() async throws {
        let api = FixtureToolAPI(); try api.append(audit); api.cancel = true
        let control = try TaskArchiveFixtureClient(client:api)
        let operation = Task { try await control.verifyNoAgentActivity() }
        do { try await operation.value; XCTFail("cancelled audit accepted") } catch {}
        XCTAssertEqual(api.calls.count,1)
    }
}
