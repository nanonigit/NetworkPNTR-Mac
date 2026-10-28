import Foundation
import XCTest
@testable import ArtexCore
@testable import VMProbe

@MainActor private final class CapturedFixtureAPI: BackendJSONTransport {
    var calls: [(String,String,Data?)] = []
    var reply = BackendHTTPResponse(status:500,body:Data())
    var cancel = false
    func send(method: String,path: String,body: Data?,bearer: String?) async throws -> BackendHTTPResponse {
        XCTAssertNil(bearer); calls.append((method,path,body))
        if cancel { withUnsafeCurrentTask { $0?.cancel() } }
        return reply
    }
    func set(_ value: [String: Any],isError: Bool = false) throws {
        let data = try JSONSerialization.data(withJSONObject:value)
        reply = .init(status:200,body:try JSONSerialization.data(withJSONObject:["is_error":isError,"output":String(decoding:data,as:UTF8.self)]))
    }
}
final class CapturedFixtureClientTests: XCTestCase {
    private func proof(preparing: Bool) -> [String: Any] {
        let zero = "foreign_tasks unsafe_tasks foreign_explorations foreign_nodes foreign_finding_nodes foreign_findings foreign_relations foreign_companies foreign_assets foreign_links foreign_events profiles task_profiles activity conversations llm_usage llm_records archives intercepts retests notification_channels notification_deliveries".split(separator:" ")
        var counts = Dictionary(uniqueKeysWithValues:zero.map{(String($0),0)})
        counts.merge(["traffic_bindings":preparing ? 0:1,"traffic_snapshots":preparing ? 0:2,"tasks":11,"explorations":11,"relations":1,"companies":1,"assets":3,"findings":33,"finding_nodes":32,"events":0]){_,new in new}
        return ["captured_native_fixture":true,"uid":1000,"finding_id":9101,"records":29,"manifest_sha256":"cbbff8fe682f4261362db3b741abeff9b429aa622c59ba4042663e512fe375ba","counts":counts]
    }
    @MainActor func testFixedGuestSourcesBoundedCodeAndOneShotPrepare() async throws {
        let api=CapturedFixtureAPI();try api.set(proof(preparing:true));let fixture=try CapturedFixtureClient(client:api)
        let value=try await fixture.prepare();XCTAssertEqual(value.records,29)
        do{_ = try await fixture.prepare();XCTFail("Reseed")}catch{}
        try api.set(proof(preparing:false));_ = try await fixture.audit()
        XCTAssertEqual(api.calls.count,2)
        for (index,call) in api.calls.enumerated() {
            XCTAssertEqual(call.0,"POST");XCTAssertEqual(call.1,"/api/tools/custom/test")
            let body=try XCTUnwrap(call.2);XCTAssertLessThan(body.count,65536)
            let json=try XCTUnwrap(JSONSerialization.jsonObject(with:body) as? [String:Any]);let exec=try XCTUnwrap(json["exec"] as? [String:Any]);let code=try XCTUnwrap(exec["code"] as? String)
            XCTAssertEqual(exec["timeout_ms"] as? Int,75000);XCTAssertTrue(code.contains(index==0 ? "fixture.prepare()":"fixture.audit()"));XCTAssertFalse(code.contains("Bearer"));XCTAssertFalse(code.contains("/Users/"))
        }
        XCTAssertEqual(Set(fixture.sourceSHA256.keys),["findings_seed_guest.py","findings_fixture_control.py","check_network.py","captured_fixture_guest.py","captured_native_guest.py"])
    }
    @MainActor func testWrongManifestCountIdentityPhaseOrActivityNeverBecomesProof() async throws {
        for mode in 0..<9 {
            let api=CapturedFixtureAPI();var value=proof(preparing:false)
            switch mode {
            case 0:value["manifest_sha256"]="wrong"
            case 1:value["records"]=28
            case 2:value["uid"]=0
            case 3:value["finding_id"]=9102
            case 4:value["captured_native_fixture"]=false
            case 5:var counts=try XCTUnwrap(value["counts"] as? [String:Int]);counts["activity"]=1;value["counts"]=counts
            case 6:value=proof(preparing:true)
            case 7:value["counts"]=[:]
            default:break
            }
            try api.set(value,isError:mode==8);let fixture=try CapturedFixtureClient(client:api)
            do{_ = try await fixture.audit();XCTFail("Wrong proof \(mode)")}catch{}
        }
    }
    @MainActor func testTransportBoundsMalformedAndCancellation() async throws {
        for mode in 0..<4 {
            let api=CapturedFixtureAPI()
            switch mode {
            case 1:api.reply = .init(status:200,body:Data(repeating:32,count:65537))
            case 2:api.reply = .init(status:200,body:Data("broken".utf8))
            case 3:try api.set(proof(preparing:false));api.cancel=true
            default:break
            }
            let fixture=try CapturedFixtureClient(client:api)
            do{_ = try await fixture.audit();XCTFail("Transport accepted")}catch{}
        }
        let api=CapturedFixtureAPI();let fixture=try CapturedFixtureClient(client:api);let pending=Task{try await fixture.audit()};pending.cancel()
        do{_ = try await pending.value;XCTFail("Cancelled")}catch{XCTAssertTrue(error is CancellationError)}
        XCTAssertTrue(api.calls.isEmpty)
    }
    @MainActor func testFailedPrepareCannotRetrySideEffects() async throws {
        let api=CapturedFixtureAPI();let fixture=try CapturedFixtureClient(client:api)
        do{_ = try await fixture.prepare();XCTFail("Expected failure")}catch{}
        try api.set(proof(preparing:true))
        do{_ = try await fixture.prepare();XCTFail("Repeated side effects")}catch{}
        XCTAssertEqual(api.calls.count,1)
    }
}
