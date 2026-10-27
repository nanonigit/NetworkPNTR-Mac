import XCTest
@testable import ArtexCore

@MainActor private final class BoundaryWire: BackendJSONTransport {
    var row: [String:Any]
    var calls = 0
    var fields: [Set<String>] = []
    var corruptAt: Int?
    var onReply: (() -> Void)?
    init() throws { row = try XCTUnwrap(FindingExerciseTestData.objects().first) }
    func send(method: String,path: String,body: Data?,bearer: String?) async throws -> BackendHTTPResponse {
        XCTAssertEqual(path,"/api/exploration/findings/9101"); XCTAssertNil(bearer); calls += 1
        if method == "PATCH" {
            let patch = try XCTUnwrap(JSONSerialization.jsonObject(with:XCTUnwrap(body)) as? [String:String])
            fields.append(Set(patch.keys))
            for (key,value) in patch { row[key] = key == "name" || key == "vulnclass" ? FindingWire.serverTrim(value) : value }
        } else { XCTAssertEqual(method,"GET"); XCTAssertNil(body) }
        if calls == corruptAt { row["summary"] = "unrelated field changed" }
        onReply?()
        return .init(status:200,body:try JSONSerialization.data(withJSONObject:row))
    }
}
final class FindingExerciseBoundaryTests: XCTestCase {
    @MainActor func testEverySingleFieldAndNormalizationResponsePreservesOtherRawFieldsAndRestoresOriginal() async throws {
        let wire = try BoundaryWire(), runner = try FindingExerciseBoundaryChecks(client:wire)
        let proof = try await runner.run()
        XCTAssertEqual(proof.requestCount,7); XCTAssertEqual(proof.diagnosticFieldBytes,8192)
        XCTAssertEqual(proof.sharedChecks,["single_name_normalized","single_class_normalized","single_severity","empty_name","diagnostic_class_8192_bytes","original_fields_restored"])
        XCTAssertEqual(proof.localChecks,["empty_patch_rejected","oversized_body_rejected","invalid_page_rejected"])
        XCTAssertEqual(wire.fields,[Set(["name"]),Set(["vulnclass"]),Set(["severity"]),Set(["name"]),Set(["vulnclass"]),Set(["name","vulnclass","severity"])])
        let original = try XCTUnwrap(FindingExerciseTestData.objects().first)
        for key in ["name","vulnclass","severity","status","summary","evidence","report"] { XCTAssertEqual(Array((wire.row[key] as! String).utf8),Array((original[key] as! String).utf8),key) }
        do { _ = try await runner.run(); XCTFail("Boundary stage replayed") } catch { }
        XCTAssertEqual(wire.calls,7)
    }
    @MainActor func testCorruptedUnrelatedFieldStopsAtEachBoundaryWithoutRetry() async throws {
        for index in 1...7 {
            let wire = try BoundaryWire(); wire.corruptAt = index
            let runner = try FindingExerciseBoundaryChecks(client:wire)
            do { _ = try await runner.run(); XCTFail("Unrelated corruption accepted") } catch { }
            XCTAssertEqual(wire.calls,index)
            do { _ = try await runner.run(); XCTFail("Failed boundary replayed") } catch { }
            XCTAssertEqual(wire.calls,index)
        }
    }
    @MainActor func testCancellationAfterAWriteDoesNotRestoreOrContinueAutomatically() async throws {
        let wire = try BoundaryWire(), runner = try FindingExerciseBoundaryChecks(client:wire)
        let work = Task { try await runner.run() }
        wire.onReply = { if wire.calls == 2 { work.cancel() } }
        do { _ = try await work.value; XCTFail("Canceled boundary accepted") } catch is CancellationError { }
        XCTAssertEqual(wire.calls,2)
        XCTAssertNotEqual(wire.row["name"] as? String,FindingExerciseFixture.initial[0].name)
    }
}
