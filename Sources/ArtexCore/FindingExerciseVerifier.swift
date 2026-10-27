import Foundation

/// Assertions on independently known fixture values, not response-derived expectations.
enum FindingExerciseVerifier {
    static func detail(_ actual: FindingRecord,expected: FindingExerciseFixture.Row) throws {
        try row(actual,expected:expected,report:expected.report)
    }
    static func page(_ actual: FindingPage,vector: FindingExerciseFixture.Vector,rows: [FindingExerciseFixture.Row]) throws {
        guard actual.total == vector.total, actual.page == vector.query.page, actual.pageSize == vector.query.size,
              actual.items.map(\.id) == vector.ids else { throw failure() }
        for value in actual.items {
            guard let expected = rows.first(where:{$0.id == value.id}) else { throw failure() }
            try row(value,expected:expected,report:"")
        }
    }
    private static func row(_ actual: FindingRecord,expected: FindingExerciseFixture.Row,report: String) throws {
        guard actual.id == expected.id, actual.findingId == expected.id, actual.taskId == expected.taskID,
              !actual.inherited, actual.sourceTaskId == nil, actual.canMutate,
              actual.severity == expected.severity.rawValue, actual.status == expected.status.rawValue,
              actual.ts == expected.timestamp, Set(actual.assets.map(\.id)) == Set(expected.assetIDs),
              [(actual.name,expected.name),(actual.vulnclass,expected.vulnclass),(actual.summary,expected.summary),
               (actual.evidence,expected.evidence),(actual.report,report)].allSatisfy({$0.0.utf8.elementsEqual($0.1.utf8)})
        else { throw failure() }
    }
    private static func failure() -> RuntimeError { .integrity("findings exercise fixture mismatch") }
}
