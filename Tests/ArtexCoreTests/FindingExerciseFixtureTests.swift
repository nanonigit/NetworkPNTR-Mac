import XCTest
@testable import ArtexCore

final class FindingExerciseFixtureTests: XCTestCase {
    func testIndependentSwiftExpectationsMatchChecksumBoundSQLDataset() throws {
        struct Seed: Decodable { let seedSourceSha256: String; let rows: [SeedRow] }
        struct SeedRow: Decodable {
            let id: Int; let taskId: Int?; let nodeId: Int?; let name: String; let vulnclass: String; let severity: String; let status: String
            let summary: String; let evidence: String; let report: String; let assetIds: [Int]; let ts: String
        }
        let url = try XCTUnwrap(Bundle.module.url(forResource:"findings-runtime-seed",withExtension:"json",subdirectory:"Fixtures"))
        let seed = try BackendJSONCoding.decode(Seed.self,from:Data(contentsOf:url))
        let source = URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("script/findings_seed_guest.py")
        XCTAssertEqual(ArtifactIntegrity.sha256(try Data(contentsOf:source)),seed.seedSourceSha256)
        XCTAssertEqual(seed.rows.count,33)
        for (expected,actual) in zip(seed.rows,FindingExerciseFixture.initial) {
            XCTAssertEqual(String(expected.id),actual.id); XCTAssertEqual(expected.taskId.map(String.init),actual.taskID); XCTAssertEqual(expected.nodeId.map(String.init),actual.nodeID)
            for (x,y) in [(expected.name,actual.name),(expected.vulnclass,actual.vulnclass),(expected.summary,actual.summary),(expected.evidence,actual.evidence),(expected.report,actual.report)] { XCTAssertEqual(Array(x.utf8),Array(y.utf8)) }
            XCTAssertEqual(expected.severity,actual.severity.rawValue); XCTAssertEqual(expected.status,actual.status.rawValue); XCTAssertEqual(expected.assetIds.map(String.init),actual.assetIDs); XCTAssertEqual(expected.ts,actual.timestamp)
        }
    }
    func testGoldenPaginationGroupsAndCombinedFilterAreNotSelfReportedCounts() throws {
        let cases = FindingExerciseFixture.vectors(rows:FindingExerciseFixture.initial)
        XCTAssertEqual(cases.count,43)
        let first = try XCTUnwrap(cases.first{$0.name == "flat_severity_1"}), second = try XCTUnwrap(cases.first{$0.name == "flat_severity_2"})
        XCTAssertEqual(first.ids.prefix(9),["9133","9129","9125","9121","9117","9113","9109","9105","9101"])
        XCTAssertEqual(first.ids.count,20); XCTAssertEqual(second.ids.count,13); XCTAssertEqual(Set(first.ids+second.ids).count,33)
        XCTAssertEqual(cases.first{$0.name == "combined"}?.ids,["9102"])
        XCTAssertEqual(cases.first{$0.name == "search_report"}?.ids,["9133"])
        XCTAssertEqual(cases.first{$0.name == "search_NFC_absent"}?.total,0)
        XCTAssertEqual(cases.first{$0.name == "asset_4"}?.total,7)
        XCTAssertEqual(FindingExerciseFixture.groups(rows:FindingExerciseFixture.initial,sort:.severity).map(\.0),["__unassigned__","8109","8105","8101","8110","8106","8102","8111","8107","8103","8108","8104"])
    }
    func testKnownMutationAndDeletionProjectionKeepsExpectedDurableCounts() {
        var rows = FindingExerciseFixture.initial
        rows[0].name = FindingExerciseFixture.editedName; rows[0].vulnclass = FindingExerciseFixture.editedClass; rows[0].severity = .low; rows[0].status = .fixed
        rows.removeAll{["9102","9133"].contains($0.id)}
        XCTAssertEqual(rows.count,31); XCTAssertEqual(rows.filter{$0.status == .pending}.count,3)
        XCTAssertEqual(FindingExerciseFixture.severities.map{level in rows.filter{$0.severity == level}.count},[7,7,8,9])
        XCTAssertEqual(rows.filter{$0.taskID == "8101"}.count,20); XCTAssertEqual(FindingExerciseFixture.groups(rows:rows,sort:.severity).count,12)
        XCTAssertEqual(FindingExerciseFixture.matching(rows,query:.init(search:FindingExerciseFixture.editedName)).map(\.id),["9101"])
    }
}
