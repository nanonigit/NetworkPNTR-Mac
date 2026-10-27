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
              !actual.inherited, actual.sourceTaskId == nil, actual.canMutate, actual.intentId == nil, actual.paramId == nil,
              actual.trafficCount == 0, actual.evidenceVersion == 0, actual.reportEvidenceVersion == 0, !actual.reportStale,
              actual.severity == expected.severity.rawValue, actual.status == expected.status.rawValue,
              actual.ts == expected.timestamp, actual.assets.count == expected.assets.count,
              zip(actual.assets,expected.assets).allSatisfy({ a,b in
                  a.id == b.id && a.type == b.type && a.label.utf8.elementsEqual(b.label.utf8)
              }),
              [(actual.name,expected.name),(actual.vulnclass,expected.vulnclass),(actual.summary,expected.summary),
               (actual.evidence,expected.evidence),(actual.report,report),(actual.taskDescription,expected.taskDescription)].allSatisfy({$0.0.utf8.elementsEqual($0.1.utf8)})
        else { throw failure() }
    }
    private static func failure() -> RuntimeError { .integrity("findings exercise fixture mismatch") }
}
