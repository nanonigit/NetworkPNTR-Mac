import XCTest
@testable import NetworkPNTRCore

@MainActor private final class FindingExerciseWire: BackendJSONTransport {
    var calls = 0
    var response = BackendHTTPResponse(status:200,body:Data("{}".utf8))
    var onReply: (() -> Void)?
    var hold = false
    var held: CheckedContinuation<BackendHTTPResponse,Error>?
    var failure = false
    func send(method: String,path: String,body: Data?,bearer: String?) async throws -> BackendHTTPResponse {
        calls += 1; XCTAssertNil(bearer)
        if hold { return try await withCheckedThrowingContinuation { held = $0 } }
        if failure { throw BackendAPIError.status(503) }; onReply?(); return response
    }
}
final class FindingExerciseTransportTests: XCTestCase {
    private let base = "/api/exploration/findings"
    @MainActor private func rejects(_ gate: FindingExerciseTransport,_ method: String = "GET",_ path: String,body: Data? = nil,bearer: String? = nil) async {
        do { _ = try await gate.send(method:method,path:path,body:body,bearer:bearer); XCTFail("Unsafe experiment request accepted") } catch { }
    }
    @MainActor func testFiniteReadVectorsAndOwnedMutationPaths() async throws {
        let api = FindingExerciseWire(), gate = try FindingExerciseTransport(client:api)
        for path in [base+"?page=1&limit=20&sort=severity",base+"/stats",base+"/groups?page=2&limit=10&sort=time",base+"/asset-tree?sort=severity",base+"?task=8111",base+"/9101?context_task=8111",base+"?page=1&limit=20&task_id=__unassigned__&asset_scope=__none__&q=a%2Bb"] {
            _ = try await gate.send(method:"GET",path:path,body:nil,bearer:nil)
        }
        _ = try await gate.send(method:"PATCH",path:base+"/9101",body:Data(#"{"name":"literal e\u0301 中文 한국어","status":"risk_accepted"}"#.utf8),bearer:nil)
        _ = try await gate.send(method:"DELETE",path:base+"/9102",body:nil,bearer:nil)
        _ = try await gate.send(method:"DELETE",path:base+"/9133",body:nil,bearer:nil)
        XCTAssertEqual(api.calls,10); XCTAssertEqual(gate.requestCount,10)
    }
    @MainActor func testForeignRoutesEncodingsTokensAndWritesNeverDispatch() async throws {
        let api = FindingExerciseWire(), gate = try FindingExerciseTransport(client:api)
        for path in ["https://outside.invalid"+base,base+"/export",base+"/9101/retest",base+"/9101/deepen",base+"/9101/lineage",base+"/9%31%30%31",base+"/9999",base+"/09101",base+"/9101#fragment","/api/tasks","/api/tools/custom/test"] { await rejects(gate,"GET",path) }
        for method in ["POST","PUT","HEAD"] { await rejects(gate,method,base) }
        await rejects(gate,"PATCH",base+"/9102",body:Data(#"{"status":"fixed"}"#.utf8))
        await rejects(gate,"DELETE",base+"/9101"); await rejects(gate,"GET",base,bearer:"never-use-this-token")
        XCTAssertEqual(api.calls,0); XCTAssertEqual(gate.requestCount,0)
    }
    @MainActor func testQueryBoundsDuplicateKeysAndWrongRouteParametersNeverDispatch() async throws {
        let api = FindingExerciseWire(), gate = try FindingExerciseTransport(client:api)
        for path in [base+"?sort=time&sort=severity",base+"?foreign=value",base+"?page=0&limit=20",base+"?page=99&limit=20",base+"?page=1&limit=200",base+"?task=7000",base+"?task_id=7000",base+"?asset_scope=a:9999",base+"?status=foreign",base+"?severity=foreign",base+"/stats?sort=time",base+"/9101?task=8101",base+"?task=8101&limit=20",base+"?q="+String(repeating:"a",count:8193)] { await rejects(gate,"GET",path) }
        XCTAssertEqual(api.calls,0)
    }
    @MainActor func testBodyValidationHasNoDispatchAndDoesNotRewriteLiteralData() async throws {
        let api = FindingExerciseWire(), gate = try FindingExerciseTransport(client:api)
        for body in [Data(),Data("[]".utf8),Data("{}".utf8),Data(#"{"sql":"unsafe"}"#.utf8),Data(#"{"name":true}"#.utf8),Data(#"{"name":null}"#.utf8),Data(#"{"status":"foreign"}"#.utf8),Data(#"{"severity":"foreign"}"#.utf8),Data(repeating:32,count:65537)] { await rejects(gate,"PATCH",base+"/9101",body:body) }
        let largeWire = try JSONEncoder().encode(["name":String(repeating:"\0",count:6000),"vulnclass":String(repeating:"\0",count:6000)])
        XCTAssertGreaterThan(largeWire.count,65536); await rejects(gate,"PATCH",base+"/9101",body:largeWire)
        let largeField = try JSONEncoder().encode(["name":String(repeating:"a",count:8193)])
        XCTAssertLessThan(largeField.count,65536); await rejects(gate,"PATCH",base+"/9101",body:largeField)
        await rejects(gate,"GET",base,body:Data("{}".utf8)); await rejects(gate,"DELETE",base+"/9102",body:Data("{}".utf8))
        XCTAssertEqual(api.calls,0)
        _ = try await gate.send(method:"PATCH",path:base+"/9101",body:Data(#"{"name":"NUL\u0000fixture"}"#.utf8),bearer:nil)
        XCTAssertEqual(api.calls,1)
    }
    @MainActor func testHardCountAndMonotonicDeadlineApplyBeforeAndAfterAwait() async throws {
        let api = FindingExerciseWire(); var instant = ContinuousClock().now
        let gate = try FindingExerciseTransport(client:api,maximumRequests:1,now:{instant})
        _ = try await gate.send(method:"GET",path:base+"/stats",body:nil,bearer:nil)
        await rejects(gate,"GET",base+"/stats"); XCTAssertEqual(api.calls,1)
        XCTAssertThrowsError(try FindingExerciseTransport(client:api,maximumRequests:0)); XCTAssertThrowsError(try FindingExerciseTransport(client:api,maximumRequests:129))
        let expired = try FindingExerciseTransport(client:api,now:{instant}); instant = instant.advanced(by:.seconds(91))
        await rejects(expired,"GET",base+"/stats"); XCTAssertEqual(api.calls,1)
        let late = try FindingExerciseTransport(client:api,now:{instant}); api.onReply = { instant = instant.advanced(by:.seconds(91)) }
        await rejects(late,"GET",base+"/stats"); XCTAssertEqual(api.calls,2); XCTAssertNil(late.lastMutationStatus)
    }
    @MainActor func testTransportErrorsAreNotRetriedAndHTTPFailureCanReachMutationState() async throws {
        let api = FindingExerciseWire(), gate = try FindingExerciseTransport(client:api)
        api.failure = true; await rejects(gate,"GET",base+"/stats"); XCTAssertEqual(api.calls,1)
        api.failure = false; api.response = .init(status:500,body:Data())
        let reply = try await gate.send(method:"PATCH",path:base+"/9101",body:Data(#"{"status":"confirmed"}"#.utf8),bearer:nil)
        XCTAssertEqual(reply.status,500); XCTAssertEqual(gate.lastMutationStatus,500); XCTAssertEqual(api.calls,2)
        api.response = .init(status:200,body:Data(repeating:0,count:4*1024*1024+1)); await rejects(gate,"GET",base+"/stats"); XCTAssertEqual(api.calls,3)
    }
    @MainActor func testCancellationBeforeAndAfterDispatchCannotYieldSuccess() async throws {
        let api = FindingExerciseWire(), gate = try FindingExerciseTransport(client:api)
        let before = Task { try await gate.send(method:"GET",path:base+"/stats",body:nil,bearer:nil) }
        before.cancel(); do { _ = try await before.value; XCTFail("Precancel accepted") } catch { }; XCTAssertEqual(api.calls,0)
        api.hold = true
        let work = Task { try await gate.send(method:"PATCH",path:base+"/9101",body:Data(#"{"status":"fixed"}"#.utf8),bearer:nil) }
        for _ in 0..<10000 { if api.held != nil { break }; await Task.yield() }
        let held = try XCTUnwrap(api.held); work.cancel(); held.resume(returning:.init(status:200,body:Data()))
        do { _ = try await work.value; XCTFail("Cancelled reply accepted") } catch { }
        XCTAssertEqual(api.calls,1); XCTAssertNil(gate.lastMutationStatus)
    }
}
