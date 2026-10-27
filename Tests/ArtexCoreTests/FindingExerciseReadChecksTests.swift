import XCTest
@testable import ArtexCore

@MainActor private final class FindingReadExerciseWire: BackendJSONTransport {
    var calls: [String] = []
    var responses: [String:BackendHTTPResponse] = [:]
    var corruptAt: Int?
    var cancelAt: Int?
    var onCancel: (() -> Void)?
    init() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource:"findings-runtime-seed",withExtension:"json",subdirectory:"Fixtures"))
        let seed = try XCTUnwrap(JSONSerialization.jsonObject(with:Data(contentsOf:url)) as? [String:Any])
        let rows = try XCTUnwrap(seed["rows"] as? [[String:Any]]).map { source in
            var row = source
            row["id"] = String(source["id"] as! Int); row["finding_id"] = row["id"]
            row["task_id"] = (source["task_id"] as? Int).map(String.init)
            row["task_description"] = (source["task_id"] as? Int).map{"F4 terminal task \($0) \(FindingExerciseFixture.literal)"} ?? ""
            row["assets"] = (source["asset_ids"] as? [Int] ?? []).map { id in
                ["id":String(id),"type":id == 8201 ? "root_domain" : (id == 8202 ? "subdomain" : "ip"),
                 "label":id == 8201 ? "fixture.example.test" : (id == 8202 ? "api.fixture.example.test" : "198.51.100.9")]
            }
            row.removeValue(forKey:"node_id"); row.removeValue(forKey:"asset_ids"); return row
        }
        for row in rows {
            responses["/api/exploration/findings/"+(row["id"] as! String)] = .init(status:200,body:try JSONSerialization.data(withJSONObject:row))
        }
        for vector in FindingExerciseFixture.vectors(rows:FindingExerciseFixture.initial) {
            let page = vector.ids.map { id -> [String:Any] in var row = rows[Int(id)!-9101]; row["report"] = ""; return row }
            responses[try vector.query.path("/api/exploration/findings",maximum:200)] = .init(status:200,body:try JSONSerialization.data(withJSONObject:["items":page,"total":vector.total,"page":vector.query.page,"pageSize":vector.query.size]))
        }
    }
    func send(method: String,path: String,body: Data?,bearer: String?) async throws -> BackendHTTPResponse {
        XCTAssertEqual(method,"GET"); XCTAssertNil(body); XCTAssertNil(bearer)
        calls.append(path)
        if calls.count == cancelAt { onCancel?() }
        if calls.count == corruptAt { return .init(status:200,body:Data("{}".utf8)) }
        return try XCTUnwrap(responses[path])
    }
}

final class FindingExerciseReadChecksTests: XCTestCase {
    @MainActor func testFiniteInitialReadStageVisitsAllVectorsAndEveryDetailExactlyOnce() async throws {
        let wire = try FindingReadExerciseWire(), stage = try FindingExerciseReadChecks(client:wire)
        let checks = try await stage.runInitial()
        XCTAssertEqual(checks.count,76); XCTAssertEqual(wire.calls.count,76)
        XCTAssertEqual(Set(wire.calls).count,76)
        XCTAssertEqual(checks.first,"flat_severity_1"); XCTAssertEqual(checks.last,"detail_9133")
        do { _ = try await stage.runInitial(); XCTFail("Stage replay accepted") } catch { }
        XCTAssertEqual(wire.calls.count,76)
    }
    @MainActor func testFirstBadPageOrDetailStopsWithoutRetryOrSuccessReport() async throws {
        for index in [1,44,76] {
            let wire = try FindingReadExerciseWire(); wire.corruptAt = index
            let stage = try FindingExerciseReadChecks(client:wire)
            do { _ = try await stage.runInitial(); XCTFail("Corrupt fixture accepted") } catch { }
            XCTAssertEqual(wire.calls.count,index)
            do { _ = try await stage.runInitial(); XCTFail("Failed stage retried") } catch { }
            XCTAssertEqual(wire.calls.count,index)
        }
    }
    @MainActor func testCancellationAtTransportReplyCannotReturnCompletedChecks() async throws {
        let wire = try FindingReadExerciseWire(), stage = try FindingExerciseReadChecks(client:wire)
        wire.cancelAt = 44
        let work = Task { try await stage.runInitial() }
        wire.onCancel = { work.cancel() }
        do { _ = try await work.value; XCTFail("Canceled stage accepted") } catch is CancellationError { }
        XCTAssertEqual(wire.calls.count,44)
    }
}
