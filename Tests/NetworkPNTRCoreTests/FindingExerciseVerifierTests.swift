import XCTest
@testable import NetworkPNTRCore

final class FindingExerciseVerifierTests: XCTestCase {
    private func objects() throws -> [[String:Any]] {
        try FindingExerciseTestData.objects()
    }
    private func record(_ value: [String:Any]) throws -> FindingRecord {
        try BackendJSONCoding.decode(FindingRecord.self,from:JSONSerialization.data(withJSONObject:value))
    }
    private func page(_ rows: [[String:Any]],total: Int = 33,page: Int = 1,size: Int = 20) throws -> FindingPage {
        try BackendJSONCoding.decode(FindingPage.self,from:JSONSerialization.data(withJSONObject:["items":rows,"total":total,"page":page,"pageSize":size]))
    }
    func testAllFixedDetailsPreserveRawBytesAndIdentity() throws {
        for (raw,expected) in zip(try objects(),FindingExerciseFixture.initial) {
            try FindingExerciseVerifier.detail(try record(raw),expected:expected)
        }
    }
    func testEveryDetailFieldMismatchIsRejectedIncludingCanonicallyEquivalentUnicode() throws {
        let original = try XCTUnwrap(objects().first), expected = FindingExerciseFixture.initial[0]
        for field in ["id","finding_id","task_id","name","vulnclass","severity","status","summary","evidence","report","ts","source_task_id"] {
            var raw = original
            raw[field] = ["id","finding_id","task_id","source_task_id"].contains(field) ? "9999" : "changed"
            XCTAssertThrowsError(try FindingExerciseVerifier.detail(record(raw),expected:expected),field)
        }
        for field in ["name","summary","evidence","report"] {
            var raw = original; raw[field] = (original[field] as! String).precomposedStringWithCanonicalMapping
            XCTAssertThrowsError(try FindingExerciseVerifier.detail(record(raw),expected:expected),field)
        }
        var raw = original; raw["inherited"] = true; raw["source_task_id"] = "8101"
        XCTAssertThrowsError(try FindingExerciseVerifier.detail(record(raw),expected:expected))
        raw = try objects()[1]; raw["assets"] = []
        XCTAssertThrowsError(try FindingExerciseVerifier.detail(record(raw),expected:FindingExerciseFixture.initial[1]))
    }
    func testAssetPresentationProvenanceAndVersionDriftAreRejected() throws {
        let original = try objects()[1], expected = FindingExerciseFixture.initial[1]
        for field in ["task_description","intent_id","param_id","traffic_count","evidence_version","report_evidence_version","report_stale"] {
            var raw = original
            if ["intent_id","param_id"].contains(field) { raw[field] = "9999" }
            else if field == "report_stale" { raw[field] = true }
            else if field == "task_description" { raw[field] = "changed" }
            else { raw[field] = 1 }
            XCTAssertThrowsError(try FindingExerciseVerifier.detail(record(raw),expected:expected),field)
        }
        let assets = try XCTUnwrap(original["assets"] as? [[String:String]])
        var raw = original; raw["assets"] = Array(assets.reversed())
        XCTAssertThrowsError(try FindingExerciseVerifier.detail(record(raw),expected:expected))
        for field in ["type","label"] {
            var changed = assets; changed[0][field] = "changed"; raw = original; raw["assets"] = changed
            XCTAssertThrowsError(try FindingExerciseVerifier.detail(record(raw),expected:expected),field)
        }
    }
    func testPaginationChecksOrderTotalAndRawFieldsWithEmptyListReport() throws {
        let all = try objects(), rows = FindingExerciseFixture.initial
        for vector in FindingExerciseFixture.vectors(rows:rows) {
            let values = vector.ids.map { id -> [String:Any] in
                var value = all[Int(id)!-9101]; value["report"] = ""; return value
            }
            let value = try page(values,total:Int(vector.total),page:Int(vector.query.page),size:vector.query.size)
            try FindingExerciseVerifier.page(value,vector:vector,rows:rows)
        }
        let vector = FindingExerciseFixture.vectors(rows:rows)[0]
        var values = vector.ids.map{all[Int($0)!-9101]}
        for i in values.indices { values[i]["report"] = "" }
        XCTAssertThrowsError(try FindingExerciseVerifier.page(page(values,total:32),vector:vector,rows:rows))
        XCTAssertThrowsError(try FindingExerciseVerifier.page(page(Array(values.reversed())),vector:vector,rows:rows))
        values[0]["summary"] = "changed"
        XCTAssertThrowsError(try FindingExerciseVerifier.page(page(values),vector:vector,rows:rows))
    }
}
