import XCTest
@testable import ArtexCore

final class FindingExerciseVerifierTests: XCTestCase {
    private func objects() throws -> [[String:Any]] {
        let url = try XCTUnwrap(Bundle.module.url(forResource:"findings-runtime-seed",withExtension:"json",subdirectory:"Fixtures"))
        let seed = try XCTUnwrap(JSONSerialization.jsonObject(with:Data(contentsOf:url)) as? [String:Any])
        return try XCTUnwrap(seed["rows"] as? [[String:Any]]).map { source in
            var row = source
            row.removeValue(forKey:"node_id"); row.removeValue(forKey:"asset_ids")
            row["id"] = String(source["id"] as! Int); row["findingId"] = row["id"]
            if let task = source["task_id"] as? Int { row["task_id"] = String(task) }
            row["assets"] = (source["asset_ids"] as? [Int] ?? []).map{["id":String($0),"type":"fixture","label":"fixture"]}
            return row
        }
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
        for field in ["id","findingId","task_id","name","vulnclass","severity","status","summary","evidence","report","ts","sourceTaskId"] {
            var raw = original
            raw[field] = ["id","findingId","task_id","sourceTaskId"].contains(field) ? "9999" : "changed"
            XCTAssertThrowsError(try FindingExerciseVerifier.detail(record(raw),expected:expected),field)
        }
        for field in ["name","summary","evidence","report"] {
            var raw = original; raw[field] = (original[field] as! String).precomposedStringWithCanonicalMapping
            XCTAssertThrowsError(try FindingExerciseVerifier.detail(record(raw),expected:expected),field)
        }
        var raw = original; raw["inherited"] = true; raw["sourceTaskId"] = "8101"
        XCTAssertThrowsError(try FindingExerciseVerifier.detail(record(raw),expected:expected))
        raw = try objects()[1]; raw["assets"] = []
        XCTAssertThrowsError(try FindingExerciseVerifier.detail(record(raw),expected:FindingExerciseFixture.initial[1]))
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
