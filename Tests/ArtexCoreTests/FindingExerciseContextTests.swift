import XCTest
@testable import ArtexCore

final class FindingExerciseContextTests: XCTestCase {
    private func decode(_ raw: Any) throws -> FindingRecord {
        try BackendJSONCoding.decode(FindingRecord.self,from:JSONSerialization.data(withJSONObject:raw))
    }
    func testEveryInitialAndPersistedTaskViewHasOrderedNodeHandlesAndLiteralContent() throws {
        for persisted in [false,true] {
            let expected = persisted ? FindingExerciseFixture.persisted : FindingExerciseFixture.initial
            for task in FindingExerciseFixture.tasks {
                let raw = try FindingExerciseTestData.taskObjects(task,persisted:persisted)
                try FindingExerciseVerifier.task(raw.map{try decode($0)},id:task,rows:expected)
            }
        }
    }
    func testInheritedAndLegacyDriftCannotPassContextVerification() throws {
        let original = try FindingExerciseTestData.taskObjects("8111"), expected = FindingExerciseFixture.initial
        XCTAssertEqual(original.count,23)
        for (index,field,value) in [(0,"finding_id","9101"),(0,"evidence","changed"),(0,"task_id","8101"),
                                     (1,"id","9131"),(2,"source_task_id","8102"),(2,"finding_id","9999"),
                                     (2,"task_description","changed"),(2,"evidence","changed")] {
            var rows = original; rows[index][field] = value
            XCTAssertThrowsError(try FindingExerciseVerifier.task(rows.map{try decode($0)},id:"8111",rows:expected),field)
        }
        var rows = original; rows[2]["inherited"] = false
        XCTAssertThrowsError(try FindingExerciseVerifier.task(rows.map{try decode($0)},id:"8111",rows:expected))
        XCTAssertThrowsError(try FindingExerciseVerifier.task(original.reversed().map{try decode($0)},id:"8111",rows:expected))
        XCTAssertThrowsError(try FindingExerciseVerifier.task(original.dropLast().map{try decode($0)},id:"8111",rows:expected))
    }
    func testContextDetailUsesStandaloneHandleAndReadOnlyInheritedProvenance() throws {
        let raw = try XCTUnwrap(FindingExerciseTestData.objects().first), expected = FindingExerciseFixture.initial[0]
        try FindingExerciseVerifier.contextualDetail(decode(raw),expected:expected,taskID:"8101")
        var inherited = raw; inherited["source_task_id"] = "8101"; inherited["inherited"] = true
        try FindingExerciseVerifier.contextualDetail(decode(inherited),expected:expected,taskID:"8111")
        XCTAssertThrowsError(try FindingExerciseVerifier.contextualDetail(decode(raw),expected:expected,taskID:"8111"))
        XCTAssertThrowsError(try FindingExerciseVerifier.contextualDetail(decode(inherited),expected:expected,taskID:"8101"))
        XCTAssertThrowsError(try FindingExerciseVerifier.contextualDetail(decode(raw),expected:expected,taskID:"8102"))
    }
}
