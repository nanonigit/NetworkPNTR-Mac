import Foundation

/// Assertions on independently known fixture values, not response-derived expectations.
enum FindingExerciseVerifier {
    static func detail(_ actual: FindingRecord,expected: FindingExerciseFixture.Row) throws {
        try row(actual,expected:expected,report:expected.report)
    }
    static func contextualDetail(_ actual: FindingRecord,expected: FindingExerciseFixture.Row,taskID: String) throws {
        let inherited = taskID == "8111" && expected.taskID == "8101"
        guard inherited || taskID == expected.taskID else { throw failure() }
        try row(actual,expected:expected,report:expected.report,inherited:inherited)
    }
    static func task(_ actual: [FindingRecord],id: String,rows: [FindingExerciseFixture.Row]) throws {
        guard FindingExerciseFixture.tasks.contains(id) else { throw failure() }
        let own = rows.filter{$0.taskID == id && $0.nodeID != nil}.sorted{$0.index > $1.index}
        let inherited = id == "8111" ? rows.filter{$0.taskID == "8101"}.sorted{$0.index > $1.index} : []
        let legacy = id == "8111"
        let expectedIDs = (legacy ? ["15190"] : []) + (own+inherited).compactMap(\.nodeID)
        guard actual.map(\.id) == expectedIDs else { throw failure() }
        if legacy { try legacyRow(actual[0]) }
        for (value,expected) in zip(actual.dropFirst(legacy ? 1 : 0),own+inherited) {
            try row(value,expected:expected,report:"",inherited:expected.taskID != id,node:true)
        }
    }
    static func page(_ actual: FindingPage,vector: FindingExerciseFixture.Vector,rows: [FindingExerciseFixture.Row]) throws {
        guard actual.total == vector.total, actual.page == vector.query.page, actual.pageSize == vector.query.size,
              actual.items.map(\.id) == vector.ids else { throw failure() }
        for value in actual.items {
            guard let expected = rows.first(where:{$0.id == value.id}) else { throw failure() }
            try row(value,expected:expected,report:"")
        }
    }
    private static func row(_ actual: FindingRecord,expected: FindingExerciseFixture.Row,report: String,inherited: Bool = false,node: Bool = false) throws {
        let evidence = node ? try BackendJSONCoding.decode(String.self,from:Data(actual.evidence.utf8)) : actual.evidence
        guard actual.id == (node ? expected.nodeID : expected.id), actual.findingId == expected.id, actual.taskId == expected.taskID,
              actual.inherited == inherited, actual.sourceTaskId == (inherited ? expected.taskID : nil), actual.canMutate == !inherited,
              actual.intentId == nil, actual.paramId == nil,
              actual.trafficCount == 0, actual.evidenceVersion == 0, actual.reportEvidenceVersion == 0, !actual.reportStale,
              actual.severity == expected.severity.rawValue, actual.status == expected.status.rawValue,
              actual.ts == expected.timestamp, actual.assets.count == expected.assets.count,
              zip(actual.assets,expected.assets).allSatisfy({ a,b in
                  a.id == b.id && a.type == b.type && a.label.utf8.elementsEqual(b.label.utf8)
              }),
              [(actual.name,expected.name),(actual.vulnclass,expected.vulnclass),(actual.summary,expected.summary),
               (evidence,expected.evidence),(actual.report,report),(actual.taskDescription,expected.taskDescription)].allSatisfy({$0.0.utf8.elementsEqual($0.1.utf8)})
        else { throw failure() }
    }
    private static func legacyRow(_ actual: FindingRecord) throws {
        let evidence = try BackendJSONCoding.decode(String.self,from:Data(actual.evidence.utf8))
        guard actual.id == "15190", actual.findingId == nil, actual.taskId == "8111", actual.sourceTaskId == nil,
              !actual.inherited, !actual.canMutate, actual.intentId == nil, actual.paramId == nil, actual.assets.isEmpty,
              actual.severity == "low", actual.status == "pending", actual.ts == "2026-10-22T10:00:59Z",
              actual.trafficCount == 0, actual.evidenceVersion == 0, actual.reportEvidenceVersion == 0, !actual.reportStale,
              [(actual.name,"F4 legacy "+FindingExerciseFixture.literal),(actual.vulnclass,"CWE-79"),
               (actual.summary,"Legacy without standalone handle"),(evidence,FindingExerciseFixture.literal),(actual.report,""),
               (actual.taskDescription,"F4 terminal task 8111 "+FindingExerciseFixture.literal)].allSatisfy({$0.0.utf8.elementsEqual($0.1.utf8)})
        else { throw failure() }
    }
    private static func failure() -> RuntimeError { .integrity("findings exercise fixture mismatch") }
}
