import Foundation
import XCTest
@testable import ArtexCore
@testable import VMProbe

@MainActor private final class EvidenceFixtureAPI: BackendJSONTransport {
    var calls: [(String, String, Data?)] = []
    var reply = BackendHTTPResponse(status: 500, body: Data())
    var cancel = false
    func send(method: String, path: String, body: Data?, bearer: String?) async throws -> BackendHTTPResponse {
        XCTAssertNil(bearer); calls.append((method, path, body))
        if cancel { withUnsafeCurrentTask { $0?.cancel() } }
        return reply
    }
    func set(_ value: [String: Any], isError: Bool = false) throws {
        let bytes = try JSONSerialization.data(withJSONObject: value)
        reply = .init(status: 200, body: try JSONSerialization.data(withJSONObject: ["is_error": isError, "output": String(decoding: bytes, as: UTF8.self)]))
    }
}
final class EvidenceFixtureClientTests: XCTestCase {
    private func proof() -> [String: Any] {
        let zero = ["foreign_tasks","unsafe_tasks","foreign_explorations","foreign_nodes","foreign_finding_nodes","foreign_findings","foreign_relations","foreign_companies","foreign_assets","foreign_links","foreign_events","profiles","task_profiles","activity","conversations","llm_usage","llm_records","archives","intercepts","retests","notification_channels","notification_deliveries"]
        var counts = Dictionary(uniqueKeysWithValues: zero.map { ($0, 0) })
        counts.merge(["traffic_bindings": 2,"traffic_snapshots": 2,"tasks": 11,"explorations": 11,"relations": 1,"companies": 1,"assets": 3,"findings": 33,"finding_nodes": 32,"events": 0]) { _, new in new }
        return ["evidence_fixture": true,"uid": 1000,"finding_id": 9101,"binding_ids": [17001,17002],"counts": counts,
                "bodies": ["literal": ["size": 52,"sha256": "e34ddc517f3d74c938352c489e37a79bd855818916bfbce320c03115d6a35224"],
                           "binary": ["size": 5242897,"sha256": "732df94bc2b263d03992bc8f8858ab72863d04ced999b95f3552fd2f48270a1d"],
                           "empty": ["size": 0,"sha256": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"],
                           "large": ["size": 135266321,"sha256": "97ac5b8e9511e77429ebaf443a3359234751dc8d3fa47b98a5c7abc51ab9d569"]]]
    }
    @MainActor func testOneShotPrepareAndRepeatableAuditUseOnlyBoundedFixedGuestCode() async throws {
        let api = EvidenceFixtureAPI(); try api.set(proof())
        let fixture = try EvidenceFixtureClient(client: api)
        let result = try await fixture.prepare(); XCTAssertEqual(result.bindingIds, [17001,17002])
        do { _ = try await fixture.prepare(); XCTFail("No repeat seed") } catch { }
        _ = try await fixture.audit()
        XCTAssertEqual(api.calls.count, 2)
        for (index, call) in api.calls.enumerated() {
            XCTAssertEqual(call.0, "POST"); XCTAssertEqual(call.1, "/api/tools/custom/test")
            let value = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(call.2)) as? [String: Any])
            XCTAssertEqual(value["kind"] as? String, "script")
            let exec = try XCTUnwrap(value["exec"] as? [String: Any]); XCTAssertEqual(exec["timeout_ms"] as? Int, 25000)
            let code = try XCTUnwrap(exec["code"] as? String)
            XCTAssertTrue(code.contains(index == 0 ? "fixture.prepare()" : "fixture.audit()"))
            XCTAssertFalse(code.contains("/Users/")); XCTAssertFalse(code.contains("shell=True"))
            XCTAssertLessThan(try XCTUnwrap(call.2).count, 65536)
        }
        XCTAssertEqual(Set(fixture.sourceSHA256.keys), ["findings_seed_guest.py","findings_fixture_control.py","evidence_fixture_guest.py"])
        XCTAssertTrue(fixture.sourceSHA256.values.allSatisfy { $0.count == 64 })
    }
    @MainActor func testWrongBodiesOwnershipActivityRowsOrErrorsNeverBecomeAcceptedProof() async throws {
        for mode in 0..<8 {
            let api = EvidenceFixtureAPI(); var value = proof()
            switch mode {
            case 0: value["uid"] = 0
            case 1: value["finding_id"] = 42
            case 2: value["binding_ids"] = [17001]
            case 3: var counts = try XCTUnwrap(value["counts"] as? [String: Int]); counts["activity"] = 1; value["counts"] = counts
            case 4: var bodies = try XCTUnwrap(value["bodies"] as? [String: Any]); bodies["large"] = ["size": 1,"sha256": "wrong"]; value["bodies"] = bodies
            case 5: value["evidence_fixture"] = false
            case 6: value["counts"] = [:]
            default: break
            }
            try api.set(value, isError: mode == 7)
            let fixture = try EvidenceFixtureClient(client: api)
            do { _ = try await fixture.audit(); XCTFail("Invalid proof accepted: \(mode)") } catch { }
            XCTAssertEqual(api.calls.count, 1)
        }
    }
    @MainActor func testStatusOversizedBodyMalformedAndCancellationFailClosed() async throws {
        for mode in 0..<4 {
            let api = EvidenceFixtureAPI()
            switch mode {
            case 0: break
            case 1: api.reply = .init(status: 200, body: Data(repeating: 32, count: 65537))
            case 2: api.reply = .init(status: 200, body: Data("bad json".utf8))
            default: try api.set(proof()); api.cancel = true
            }
            let fixture = try EvidenceFixtureClient(client: api)
            let pending = Task { try await fixture.audit() }
            do { _ = try await pending.value; XCTFail("Rejected reply") } catch { }
        }
        let api = EvidenceFixtureAPI(); try api.set(proof()); let fixture = try EvidenceFixtureClient(client: api)
        let pending = Task { try await fixture.audit() }; pending.cancel()
        do { _ = try await pending.value; XCTFail("Precancel") } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertTrue(api.calls.isEmpty)
    }
}
