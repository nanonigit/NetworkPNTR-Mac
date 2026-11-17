import XCTest
@testable import NetworkPNTRCore

@MainActor final class FindingMutationExerciseWire: BackendJSONTransport {
    var rows: [String:[String:Any]] = [:]
    var calls: [(String,String)] = []
    var partialCommit = true
    var partialHTTPStatus = 500
    var corruptSuccess = false
    var onPartial: (() -> Void)?
    init() throws {
        for row in try FindingExerciseTestData.objects() { rows[row["id"] as! String] = row }
    }
    func response(_ value: Any,status: Int = 200) throws -> BackendHTTPResponse {
        .init(status:status,body:try JSONSerialization.data(withJSONObject:value))
    }
    func send(method: String,path: String,body: Data?,bearer: String?) async throws -> BackendHTTPResponse {
        calls.append((method,path)); XCTAssertNil(bearer)
        let url = try XCTUnwrap(URLComponents(string:path))
        let id = String(url.path.split(separator:"/").last ?? "")
        if method == "GET", id == "findings" {
            let ids = FindingExerciseFixture.vectors(rows:FindingExerciseFixture.initial)[0].ids
            let values = ids.map { id -> [String:Any] in var row = rows[id]!; row["report"] = ""; return row }
            return try response(["items":values,"total":33,"page":1,"page_size":20])
        }
        guard var row = rows[id] else { return .init(status:404,body:Data()) }
        if method == "GET" { return try response(row) }
        if method == "DELETE" {
            XCTAssertTrue(["9102","9133"].contains(id)); rows.removeValue(forKey:id)
            return try response(["deleted":true,"id":Int(id)!])
        }
        XCTAssertEqual(method,"PATCH"); XCTAssertEqual(id,"9101")
        let fields = try XCTUnwrap(JSONSerialization.jsonObject(with:XCTUnwrap(body)) as? [String:String])
        let partial = fields["name"]?.contains("\0") == true
        if let status = fields["status"], !partial || partialCommit { row["status"] = status }
        if partial {
            rows[id] = row; onPartial?()
            return .init(status:partialHTTPStatus,body:Data("{\"error\":\"fixture PostgreSQL text failure\"}".utf8))
        }
        for field in ["name","vulnclass","severity"] { if let value = fields[field] { row[field] = value } }
        rows[id] = row
        if corruptSuccess { return .init(status:200,body:Data("{}".utf8)) }
        return try response(row)
    }
}

final class FindingExerciseMutationTests: XCTestCase {
    @MainActor func testSeparateEditsRealisticPartialFailureExplicitAckAndDeletesUseFiniteIDs() async throws {
        let wire = try FindingMutationExerciseWire(), exercise = try FindingExerciseMutationChecks(client:wire)
        let proof = try await exercise.run()
        XCTAssertEqual(proof.checks,FindingExerciseMutationChecks.expectedChecks)
        XCTAssertEqual(proof.partialHTTPStatus,500); XCTAssertEqual(proof.requestCount,14)
        XCTAssertEqual(wire.calls.filter{$0.0 == "PATCH"}.count,4)
        XCTAssertEqual(wire.calls.filter{$0.0 == "DELETE"}.map(\.1),["/api/exploration/findings/9102","/api/exploration/findings/9133"])
        XCTAssertEqual(wire.rows.count,31); XCTAssertEqual(wire.rows["9101"]?["status"] as? String,"fixed")
        XCTAssertEqual(wire.rows["9101"]?["name"] as? String,FindingExerciseFixture.editedName)
        do { _ = try await exercise.run(); XCTFail("Mutation stage replayed") } catch { }
        XCTAssertEqual(wire.calls.count,14)
    }
    @MainActor func testFailureWithoutPartialCommitOrWrongHTTPStatusCannotClaimPartialWitness() async throws {
        for noCommit in [false,true] {
            let wire = try FindingMutationExerciseWire()
            if noCommit { wire.partialCommit = false } else { wire.partialHTTPStatus = 400 }
            let exercise = try FindingExerciseMutationChecks(client:wire)
            do { _ = try await exercise.run(); XCTFail("False partial witness accepted") } catch { }
            XCTAssertEqual(wire.calls.filter{$0.0 == "PATCH"}.count,3)
            XCTAssertFalse(wire.calls.contains{$0.0 == "DELETE"})
            let count = wire.calls.count
            do { _ = try await exercise.run(); XCTFail("Failed mutation stage retried") } catch { }
            XCTAssertEqual(wire.calls.count,count)
        }
    }
    @MainActor func testMalformedWriteSuccessStopsBeforeFurtherMutation() async throws {
        let wire = try FindingMutationExerciseWire(); wire.corruptSuccess = true
        let exercise = try FindingExerciseMutationChecks(client:wire)
        do { _ = try await exercise.run(); XCTFail("Malformed success accepted") } catch { }
        XCTAssertEqual(wire.calls.count,3); XCTAssertEqual(wire.calls.filter{$0.0 == "PATCH"}.count,1)
    }
    @MainActor func testCancellationAfterPartialWriteNeverAcknowledgesOrContinues() async throws {
        let wire = try FindingMutationExerciseWire(), exercise = try FindingExerciseMutationChecks(client:wire)
        let work = Task { try await exercise.run() }; wire.onPartial = { work.cancel() }
        do { _ = try await work.value; XCTFail("Canceled write accepted") } catch is CancellationError { }
        XCTAssertEqual(wire.calls.count,5)
        XCTAssertEqual(wire.rows["9101"]?["status"] as? String,"risk_accepted")
        XCTAssertFalse(wire.calls.contains{$0.0 == "DELETE"})
    }
}
