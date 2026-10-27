import XCTest
@testable import ArtexCore

final class FindingExerciseAggregateTests: XCTestCase {
    private func snapshots() throws -> [([String:Any],[FindingExerciseFixture.Row])] {
        let url = try XCTUnwrap(Bundle.module.url(forResource:"findings-runtime-aggregates",withExtension:"json",subdirectory:"Fixtures"))
        let file = try XCTUnwrap(JSONSerialization.jsonObject(with:Data(contentsOf:url)) as? [String:Any])
        let seed = URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("script/findings_seed_guest.py")
        XCTAssertEqual(file["seed_source_sha256"] as? String,ArtifactIntegrity.sha256(try Data(contentsOf:seed)))
        return [(try XCTUnwrap(file["initial"] as? [String:Any]),FindingExerciseFixture.initial),
                (try XCTUnwrap(file["persisted"] as? [String:Any]),FindingExerciseFixture.persisted)]
    }
    private func decode<T: Decodable>(_ type: T.Type,_ value: Any) throws -> T {
        try BackendJSONCoding.decode(type,from:JSONSerialization.data(withJSONObject:value))
    }
    func testIndependentInitialAndDurableAggregateGoldens() throws {
        for (raw,rows) in try snapshots() {
            try FindingExerciseAggregateVerifier.stats(decode(FindingStats.self,raw["stats"]!),rows:rows)
            try FindingExerciseAggregateVerifier.tree(decode(FindingAssetTree.self,raw["tree"]!),rows:rows)
            let groups = try XCTUnwrap(raw["groups"] as? [[String:Any]])
            for sort in [FindingSort.severity,.time] {
                let ordered = sort == .severity ? groups : groups.sorted{($0["last_found_at"] as! String) > ($1["last_found_at"] as! String)}
                for page in 1...3 {
                    let items = Array(ordered.dropFirst((page-1)*10).prefix(10))
                    let value: [String:Any] = ["items":items,"total":12,"finding_total":rows.count,"page":page,"page_size":10]
                    try FindingExerciseAggregateVerifier.groups(decode(FindingGroupsPage.self,value),query:.init(page:Int64(page),size:10,sort:sort),rows:rows)
                }
            }
        }
    }
    func testStatsRejectEveryCounterAndOptionValueOrOrderDrift() throws {
        let (raw,rows) = try snapshots()[0], original = try XCTUnwrap(raw["stats"] as? [String:Any])
        for key in ["total","pending","critical","high","medium","low"] {
            var changed = original; changed[key] = (original[key] as! Int)+1
            XCTAssertThrowsError(try FindingExerciseAggregateVerifier.stats(decode(FindingStats.self,changed),rows:rows),key)
        }
        let classes = try XCTUnwrap(original["vulnclasses"] as? [String])
        var changed = original; changed["vulnclasses"] = Array(classes.reversed())
        XCTAssertThrowsError(try FindingExerciseAggregateVerifier.stats(decode(FindingStats.self,changed),rows:rows))
        var tasks = try XCTUnwrap(original["tasks"] as? [[String:Any]])
        for field in ["name","description","count","id"] {
            var values = tasks; values[0][field] = field == "count" || field == "id" ? 9999 : "changed"
            changed = original; changed["tasks"] = values
            XCTAssertThrowsError(try FindingExerciseAggregateVerifier.stats(decode(FindingStats.self,changed),rows:rows),field)
        }
        tasks.reverse(); changed = original; changed["tasks"] = tasks
        XCTAssertThrowsError(try FindingExerciseAggregateVerifier.stats(decode(FindingStats.self,changed),rows:rows))
    }
    func testTreeRejectsOrderHierarchyIdentityLabelsCountsAndTruncationDrift() throws {
        let (raw,rows) = try snapshots()[0], original = try XCTUnwrap(raw["tree"] as? [String:Any])
        let nodes = try XCTUnwrap(original["nodes"] as? [[String:Any]])
        for key in ["kind","label","parent","asset_id","company_id","self","total","critical","high","medium","low","last_found_at"] {
            var values = nodes
            values[1][key] = ["asset_id","company_id","self","total","critical","high","medium","low"].contains(key) ? 9999 : "changed"
            var changed = original; changed["nodes"] = values
            XCTAssertThrowsError(try FindingExerciseAggregateVerifier.tree(decode(FindingAssetTree.self,changed),rows:rows),key)
        }
        var changed = original; changed["nodes"] = Array(nodes.reversed())
        XCTAssertThrowsError(try FindingExerciseAggregateVerifier.tree(decode(FindingAssetTree.self,changed),rows:rows))
        for key in ["truncated","dropped_kinds","finding_total"] {
            changed = original
            switch key { case "truncated": changed[key] = true; case "dropped_kinds": changed[key] = ["endpoint"]; default: changed[key] = 32 }
            XCTAssertThrowsError(try FindingExerciseAggregateVerifier.tree(decode(FindingAssetTree.self,changed),rows:rows),key)
        }
    }
    func testGroupMetadataBucketsTotalsAndOrderAreVerified() throws {
        let (raw,rows) = try snapshots()[0], groups = try XCTUnwrap(raw["groups"] as? [[String:Any]])
        let original: [String:Any] = ["items":Array(groups.prefix(10)),"total":12,"finding_total":33,"page":1,"page_size":10]
        for key in ["task_id","task_name","task_description","task_status","count","critical","high","medium","low","last_found_at"] {
            var items = Array(groups.prefix(10)); items[1][key] = ["task_id","count","critical","high","medium","low"].contains(key) ? 9999 : "changed"
            var changed = original; changed["items"] = items
            XCTAssertThrowsError(try FindingExerciseAggregateVerifier.groups(decode(FindingGroupsPage.self,changed),query:.init(size:10),rows:rows),key)
        }
        for key in ["total","finding_total","page","page_size"] {
            var changed = original; changed[key] = (original[key] as! Int)+1
            XCTAssertThrowsError(try FindingExerciseAggregateVerifier.groups(decode(FindingGroupsPage.self,changed),query:.init(size:10),rows:rows),key)
        }
        var changed = original; changed["items"] = Array(groups.prefix(10).reversed())
        XCTAssertThrowsError(try FindingExerciseAggregateVerifier.groups(decode(FindingGroupsPage.self,changed),query:.init(size:10),rows:rows))
    }
}
