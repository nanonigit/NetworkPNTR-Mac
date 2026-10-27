import XCTest
@testable import ArtexCore
@testable import VMProbe

@MainActor private final class FindingFixtureToolAPI: BackendJSONTransport {
    var calls: [(String,String,Data?)] = []
    var replies: [BackendHTTPResponse] = []
    var cancel = false
    func send(method: String,path: String,body: Data?,bearer: String?) async throws -> BackendHTTPResponse {
        XCTAssertNil(bearer); calls.append((method,path,body))
        if cancel { withUnsafeCurrentTask{$0?.cancel()} }
        return replies.removeFirst()
    }
    func append(_ output: Any,isError: Bool = false) throws {
        let data = try JSONSerialization.data(withJSONObject:output)
        let body: [String:Any] = ["is_error":isError,"output":String(data:data,encoding:.utf8)!]
        replies.append(.init(status:200,body:try JSONSerialization.data(withJSONObject:body)))
    }
}
final class FindingFixtureClientTests: XCTestCase {
    private let zero = ["foreign_tasks","unsafe_tasks","foreign_explorations","foreign_nodes","foreign_finding_nodes",
        "foreign_findings","foreign_relations","foreign_companies","foreign_assets","foreign_links","foreign_events",
        "profiles","task_profiles","activity","conversations","llm_usage","llm_records","archives","intercepts","retests",
        "traffic_bindings","traffic_snapshots","notification_channels","notification_deliveries"]
    private func audit(fresh: Bool = false) -> [String:Any] {
        var counts: [String:Int] = [:]
        for key in zero { counts[key] = 0 }
        counts["tasks"] = fresh ? 0 : 11; counts["explorations"] = fresh ? 0 : 11
        counts["relations"] = fresh ? 0 : 1; counts["companies"] = fresh ? 0 : 1; counts["assets"] = fresh ? 0 : 3
        counts["findings"] = fresh ? 0 : 33; counts["finding_nodes"] = fresh ? 0 : 32; counts["events"] = 0
        return ["fixture_audit":true,"uid":1000,"fresh":fresh,"counts":counts]
    }
    private var seed: [String:Any] {
        ["fixture_seeded":true,"task_ids":Array(8101...8111),"finding_ids":Array(9101...9133),"legacy_node_id":15190,"asset_ids":[8201,8202,8203]]
    }
    @MainActor func testOneShotSeedUsesOnlyFixedGuestScriptsAndAuditsBothSides() async throws {
        let api = FindingFixtureToolAPI(); try api.append(audit(fresh:true)); try api.append(seed); try api.append(audit())
        let fixture = try FindingFixtureClient(client:api); try await fixture.seed()
        XCTAssertEqual(api.calls.count,3)
        for call in api.calls {
            XCTAssertEqual(call.0,"POST"); XCTAssertEqual(call.1,"/api/tools/custom/test")
            let request = try XCTUnwrap(JSONSerialization.jsonObject(with:XCTUnwrap(call.2)) as? [String:Any])
            XCTAssertEqual(request["kind"] as? String,"script")
            let exec = try XCTUnwrap(request["exec"] as? [String:Any]); XCTAssertEqual(exec["timeout_ms"] as? Int,20000)
            let code = try XCTUnwrap(exec["code"] as? String)
            XCTAssertTrue(code.contains("ARTEX_FINDINGS_FIXTURE")); XCTAssertFalse(code.contains("/Users/"))
        }
        let root = URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        XCTAssertEqual(fixture.seedSHA256,ArtifactIntegrity.sha256(try Data(contentsOf:root.appendingPathComponent("script/findings_seed_guest.py"))))
        XCTAssertEqual(fixture.controlSHA256,ArtifactIntegrity.sha256(try Data(contentsOf:root.appendingPathComponent("script/findings_fixture_control.py"))))
        do { try await fixture.seed(); XCTFail("Seed replayed") } catch { }
        XCTAssertEqual(api.calls.count,3)
    }
    @MainActor func testEveryForeignCountMissingKeyAndOwnedStateMismatchRejectsAudit() async throws {
        let original = audit(), counts = original["counts"] as! [String:Int]
        var variants: [[String:Any]] = []
        for key in zero+["tasks","explorations","relations","companies","assets","findings","finding_nodes","events"] {
            var changed = original, values = counts; values[key] = 999; changed["counts"] = values; variants.append(changed)
        }
        var changed = original, missing = counts; missing.removeValue(forKey:"foreign_tasks"); changed["counts"] = missing; variants.append(changed)
        changed = original; changed["fresh"] = true; variants.append(changed)
        changed = original; changed["uid"] = 0; variants.append(changed)
        changed = original; changed["fixture_audit"] = false; variants.append(changed)
        for value in variants {
            let api = FindingFixtureToolAPI(); try api.append(value); let fixture = try FindingFixtureClient(client:api)
            do { try await fixture.verifyNoAgentActivity(); XCTFail("Invalid audit accepted") } catch { }
            XCTAssertEqual(api.calls.count,1)
        }
    }
    @MainActor func testBadSeedProofOrFreshAuditStopsWithoutRetry() async throws {
        for key in ["fixture_seeded","task_ids","finding_ids","legacy_node_id","asset_ids"] {
            var changed = seed
            switch key { case "fixture_seeded": changed[key] = false; case "legacy_node_id": changed[key] = 15191; default: changed[key] = [9999] }
            let api = FindingFixtureToolAPI(); try api.append(audit(fresh:true)); try api.append(changed)
            let fixture = try FindingFixtureClient(client:api)
            do { try await fixture.seed(); XCTFail(key) } catch { }
            XCTAssertEqual(api.calls.count,2)
            do { try await fixture.seed(); XCTFail("Failed seed replayed") } catch { }
            XCTAssertEqual(api.calls.count,2)
        }
        let api = FindingFixtureToolAPI(); try api.append(audit())
        let fixture = try FindingFixtureClient(client:api)
        do { try await fixture.seed(); XCTFail("Nonempty seed accepted") } catch { }
        XCTAssertEqual(api.calls.count,1)
    }
    @MainActor func testLateCancellationToolFailureAndOversizedResponsesNeverPass() async throws {
        let api = FindingFixtureToolAPI(); try api.append(audit()); api.cancel = true
        let fixture = try FindingFixtureClient(client:api)
        let work = Task { try await fixture.verifyNoAgentActivity() }
        do { try await work.value; XCTFail("Canceled audit accepted") } catch is CancellationError { }
        for response in [BackendHTTPResponse(status:503,body:Data()),.init(status:200,body:Data(repeating:32,count:65537)),
                         .init(status:200,body:Data("{}".utf8))] {
            let api = FindingFixtureToolAPI(); api.replies = [response]
            do { try await FindingFixtureClient(client:api).verifyNoAgentActivity(); XCTFail("Bad tool reply accepted") } catch { }
            XCTAssertEqual(api.calls.count,1)
        }
        let failed = FindingFixtureToolAPI(); try failed.append(audit(),isError:true)
        do { try await FindingFixtureClient(client:failed).verifyNoAgentActivity(); XCTFail("Tool error accepted") } catch { }
    }
}
