import XCTest
@testable import ArtexCore

@MainActor final class FindingReadExerciseWire: BackendJSONTransport {
    var calls: [String] = []
    var responses: [String:BackendHTTPResponse] = [:]
    var corruptAt: Int?
    var cancelAt: Int?
    var onCancel: (() -> Void)?
    init(persisted: Bool = false) throws {
        var rows = try FindingExerciseTestData.objects()
        let expected = persisted ? FindingExerciseFixture.persisted : FindingExerciseFixture.initial
        if persisted {
            rows.removeAll{["9102","9133"].contains($0["id"] as! String)}
            rows[0]["name"] = FindingExerciseFixture.editedName; rows[0]["vulnclass"] = FindingExerciseFixture.editedClass
            rows[0]["severity"] = "low"; rows[0]["status"] = "fixed"
        }
        for row in rows {
            responses["/api/exploration/findings/"+(row["id"] as! String)] = .init(status:200,body:try JSONSerialization.data(withJSONObject:row))
        }
        for vector in FindingExerciseFixture.vectors(rows:expected) {
            let page = vector.ids.map { id -> [String:Any] in var row = rows.first{$0["id"] as? String == id}!; row["report"] = ""; return row }
            responses[try vector.query.path("/api/exploration/findings",maximum:200)] = .init(status:200,body:try JSONSerialization.data(withJSONObject:["items":page,"total":vector.total,"page":vector.query.page,"pageSize":vector.query.size]))
        }
        let url = try XCTUnwrap(Bundle.module.url(forResource:"findings-runtime-aggregates",withExtension:"json",subdirectory:"Fixtures"))
        let file = try XCTUnwrap(JSONSerialization.jsonObject(with:Data(contentsOf:url)) as? [String:Any])
        let snapshot = try XCTUnwrap(file[persisted ? "persisted" : "initial"] as? [String:Any])
        responses["/api/exploration/findings/stats"] = .init(status:200,body:try JSONSerialization.data(withJSONObject:snapshot["stats"]!))
        let treePath = try FindingQuery().path("/api/exploration/findings/asset-tree",includeScope:false)
        responses[treePath] = .init(status:200,body:try JSONSerialization.data(withJSONObject:snapshot["tree"]!))
        let groups = try XCTUnwrap(snapshot["groups"] as? [[String:Any]])
        for sort in [FindingSort.severity,.time] {
            let ordered = sort == .severity ? groups : groups.sorted{($0["last_found_at"] as! String) > ($1["last_found_at"] as! String)}
            for page in 1...(sort == .severity ? 3 : 2) {
                let query = FindingQuery(page:Int64(page),size:10,sort:sort)
                let path = try query.path("/api/exploration/findings/groups",maximum:100)
                let body: [String:Any] = ["items":Array(ordered.dropFirst((page-1)*10).prefix(10)),"total":12,"finding_total":rows.count,"page":page,"page_size":10]
                responses[path] = .init(status:200,body:try JSONSerialization.data(withJSONObject:body))
            }
        }
        for page in 1...3 {
            let query = FindingQuery(page:Int64(page),task:"8101")
            let found = FindingExerciseFixture.matching(expected,query:query)
            let values = found.dropFirst((page-1)*20).prefix(20).map { row -> [String:Any] in
                var value = rows.first{$0["id"] as? String == row.id}!; value["report"] = ""; return value
            }
            let body: [String:Any] = ["items":values,"total":found.count,"page":page,"page_size":20]
            responses[try query.path("/api/exploration/findings",maximum:200)] = .init(status:200,body:try JSONSerialization.data(withJSONObject:body))
        }
        for task in FindingExerciseFixture.tasks {
            let body = try FindingExerciseTestData.taskObjects(task,persisted:persisted)
            responses["/api/exploration/findings?task="+task] = .init(status:200,body:try JSONSerialization.data(withJSONObject:body))
        }
        let detail = rows.first{$0["id"] as? String == "9101"}!
        responses["/api/exploration/findings/9101?context_task=8101"] = .init(status:200,body:try JSONSerialization.data(withJSONObject:detail))
        var inherited = detail; inherited["source_task_id"] = "8101"; inherited["inherited"] = true
        responses["/api/exploration/findings/9101?context_task=8111"] = .init(status:200,body:try JSONSerialization.data(withJSONObject:inherited))
        responses["/api/exploration/findings/9101?context_task=8102"] = .init(status:404,body:Data())
        if persisted {
            for id in ["9102","9133"] { responses["/api/exploration/findings/"+id] = .init(status:404,body:Data()) }
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
        XCTAssertEqual(checks.count,100); XCTAssertEqual(wire.calls.count,100)
        XCTAssertEqual(Set(wire.calls).count,100)
        XCTAssertEqual(checks.first,"flat_severity_1"); XCTAssertEqual(checks.last,"unrelated_context_rejected")
        do { _ = try await stage.runInitial(); XCTFail("Stage replay accepted") } catch { }
        XCTAssertEqual(wire.calls.count,100)
    }
    @MainActor func testPersistedStageVerifiesEditsDeletionsAggregatesAndTaskNodes() async throws {
        let wire = try FindingReadExerciseWire(persisted:true), stage = try FindingExerciseReadChecks(client:wire)
        let checks = try await stage.runPersisted()
        XCTAssertEqual(checks.count,100); XCTAssertEqual(wire.calls.count,100)
        XCTAssertEqual(checks.suffix(2),["deleted_9102","deleted_9133"])
        XCTAssertEqual(Set(wire.calls).count,100)
    }
    @MainActor func testFirstBadPageOrDetailStopsWithoutRetryOrSuccessReport() async throws {
        for index in [1,44,76,77,99,100] {
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
