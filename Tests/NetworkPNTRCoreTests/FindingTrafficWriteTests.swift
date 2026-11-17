import XCTest
@testable import NetworkPNTRCore

@MainActor private final class TrafficWriteAPI: BackendJSONTransport {
    struct Call { let method, path: String; let body: Data? }
    var calls: [Call] = []
    var replies: [BackendHTTPResponse] = []
    var cancel = false
    func send(method: String,path: String,body: Data?,bearer: String?) async throws -> BackendHTTPResponse {
        XCTAssertNil(bearer);calls.append(.init(method:method,path:path,body:body))
        if cancel {withUnsafeCurrentTask{$0?.cancel()}}
        guard !replies.isEmpty else {throw BackendAPIError.invalidResponse};return replies.removeFirst()
    }
}
final class FindingTrafficWriteTests: XCTestCase {
    private func decode<T: Decodable>(_ type: T.Type,_ value: Any) throws -> T {
        try BackendJSONCoding.decode(type,from:JSONSerialization.data(withJSONObject:value))
    }
    private func target(_ changes: [String:Any] = [:]) throws -> FindingRecord {
        var value: [String:Any] = ["id":"41","finding_id":"9101","task_id":"8101","name":"raw","vulnclass":"CWE-79","severity":"high","status":"pending","summary":"","evidence":"","ts":"2026-10-22T10:00:00Z"]
        value.merge(changes,uniquingKeysWith:{$1});return try decode(FindingRecord.self,value)
    }
    private func summary(version: Int64 = 2,ids: [String] = ["1","2"],owner: String = "9101") throws -> [String:Any] {
        let path=try XCTUnwrap(Bundle.module.url(forResource:"Fixtures/findings-traffic-contract",withExtension:"json"))
        let fixture=try XCTUnwrap(JSONSerialization.jsonObject(with:Data(contentsOf:path)) as? [String:Any])
        let template=try XCTUnwrap(fixture["binding"] as? [String:Any])
        let bindings=ids.enumerated().map {index,id -> [String:Any] in
            var row=template;row["id"]=id;row["finding_id"]=owner;row["position"]=index;return row
        }
        return ["finding_id":owner,"version":version,"report_version":1,"bindings":bindings]
    }
    @MainActor private func add(_ api: TrafficWriteAPI,version: Int64 = 3,ids: [String] = ["1","2"],owner: String = "9101",status: Int = 200) throws {
        api.replies.append(.init(status:status,body:try JSONSerialization.data(withJSONObject:summary(version:version,ids:ids,owner:owner))))
    }
    private func body(_ call: TrafficWriteAPI.Call) throws -> [String:Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with:XCTUnwrap(call.body)) as? [String:Any])
    }
    @MainActor func testAllFourMethodsBodiesContextAndExactLargeVersion() async throws {
        let api=TrafficWriteAPI(),service=FindingTrafficService(client:api),row=try target()
        let old=try decode(FindingTraffic.self,summary(version:9007199254740993))
        let note="\u{feff}e\u{301} 中文 한국어"
        try add(api,version:old.version)
        let bound=try await service.apply(.bind([.init(trafficId:" \u{85} opaque+id \u{85} ",role:.proof,note:note),.init(trafficId:"opaque+id")]),to:row,snapshot:old,contextTaskID:"8101")
        XCTAssertEqual(bound.version,old.version);XCTAssertEqual(api.calls[0].method,"POST")
        XCTAssertEqual(api.calls[0].path,"/api/exploration/findings/9101/traffic?context_task=8101")
        let bind=try body(api.calls[0]);XCTAssertEqual(Set(bind.keys),["traffic_refs"])
        let refs=try XCTUnwrap(bind["traffic_refs"] as? [[String:Any]]);XCTAssertEqual(refs.count,2)
        XCTAssertEqual(refs[0]["traffic_id"] as? String," \u{85} opaque+id \u{85} ")
        // JSONSerialization can strip leading FEFF; inspect wire content with the typed decoder instead.
        struct Ref: Decodable { let note: String }
        struct Refs: Decodable { let trafficRefs: [Ref] }
        let wireRefs=try BackendJSONCoding.decode(Refs.self,from:XCTUnwrap(api.calls[0].body))
        XCTAssertEqual(Array(wireRefs.trafficRefs[0].note.utf8),Array(note.utf8))
        XCTAssertEqual(refs[1]["role"] as? String,"supporting");XCTAssertEqual(refs[1]["note"] as? String,"")
        for role in FindingTrafficRole.allCases {
            try add(api,version:old.version+2)
            _ = try await service.apply(.edit(bindingID:"01",role:role,note:note),to:row,snapshot:old,contextTaskID:"8101")
            let call=try XCTUnwrap(api.calls.last),payload=try body(call)
            XCTAssertEqual(call.method,"PATCH");XCTAssertEqual(call.path,"/api/exploration/findings/9101/traffic/1?context_task=8101")
            XCTAssertEqual(Set(payload.keys),["version","role","note"]);XCTAssertEqual(payload["role"] as? String,role.rawValue)
            XCTAssertEqual((payload["version"] as? NSNumber)?.int64Value,old.version)
        }
        try add(api,version:old.version+1,ids:["2"])
        _ = try await service.apply(.remove(bindingID:"1"),to:row,snapshot:old)
        XCTAssertEqual(api.calls.last?.method,"DELETE");XCTAssertEqual(Set(try body(XCTUnwrap(api.calls.last)).keys),["version"])
        try add(api,version:old.version+1,ids:["2","1"])
        _ = try await service.apply(.reorder(["2","01"]),to:row,snapshot:old)
        let order=try body(XCTUnwrap(api.calls.last));XCTAssertEqual(api.calls.last?.method,"PUT")
        XCTAssertEqual(api.calls.last?.path,"/api/exploration/findings/9101/traffic/order")
        XCTAssertEqual(Set(order.keys),["version","binding_ids"]);XCTAssertEqual(order["binding_ids"] as? [String],["2","1"])
    }
    @MainActor func testInvalidCapturedTargetsMembershipPermutationsAndBodyNeverDispatch() async throws {
        let api=TrafficWriteAPI(),service=FindingTrafficService(client:api),row=try target(),old=try decode(FindingTraffic.self,summary())
        for change: FindingTrafficChange in [.bind([]),.bind([.init(trafficId:" \u{85}\t")]),.edit(bindingID:"3",role:.proof,note:""),.remove(bindingID:"../1"),.reorder(["1"]),.reorder(["1","01"]),.reorder(["1","3"]),.bind([.init(trafficId:"x",note:String(repeating:"x",count:1024*1024))])] {
            do {_ = try await service.apply(change,to:row,snapshot:old);XCTFail("invalid command dispatched")}catch {}
        }
        for bad in [try target(["inherited":true,"source_task_id":"8101"]),try target(["finding_id":NSNull()]),try target(["finding_id":"99"])] {
            do {_ = try await service.apply(.remove(bindingID:"1"),to:bad,snapshot:old);XCTFail()}catch {}
        }
        for context in ["../1","0","8102"] {
            do {_ = try await service.apply(.remove(bindingID:"1"),to:row,snapshot:old,contextTaskID:context);XCTFail()}catch {}
        }
        XCTAssertTrue(api.calls.isEmpty)
        try add(api,version:3,ids:[])
        let empty=try decode(FindingTraffic.self,summary(ids:[]))
        _ = try await service.apply(.reorder([]),to:row,snapshot:empty)
        XCTAssertEqual(api.calls.count,1)
    }
    @MainActor func testWriteOwnerAndVersionCannotLieAndBindNeedNotAdvance() async throws {
        let api=TrafficWriteAPI(),service=FindingTrafficService(client:api),row=try target(),old=try decode(FindingTraffic.self,summary())
        for reply in [try summary(owner:"99"),try summary(version:2),try summary(version:1)] {
            api.replies.append(.init(status:200,body:try JSONSerialization.data(withJSONObject:reply)))
            do {_ = try await service.apply(.edit(bindingID:"1",role:.baseline,note:""),to:row,snapshot:old);XCTFail()}catch {}
        }
        try add(api,version:2)
        let unchanged=try await service.apply(.bind([.init(trafficId:"existing")]),to:row,snapshot:old)
        XCTAssertEqual(unchanged.version,2)
        try add(api,version:1)
        do {_ = try await service.apply(.bind([.init(trafficId:"existing")]),to:row,snapshot:old);XCTFail("regressed bind version accepted")}catch {}
    }
    @MainActor func testErrorsAndCancellationDoNotReplayEvenOnConflict() async throws {
        let api=TrafficWriteAPI(),service=FindingTrafficService(client:api),row=try target(),old=try decode(FindingTraffic.self,summary())
        let cancelled=Task {@MainActor in
            withUnsafeCurrentTask{$0?.cancel()}
            return try await service.apply(.remove(bindingID:"1"),to:row,snapshot:old)
        }
        do {_ = try await cancelled.value;XCTFail()}catch is CancellationError {}catch {XCTFail()}
        XCTAssertTrue(api.calls.isEmpty)
        for status in [201,204,401,403,404,409,422,500] {
            try add(api,status:status)
            do {_ = try await service.apply(.remove(bindingID:"1"),to:row,snapshot:old);XCTFail()}
            catch BackendAPIError.status(let code) {XCTAssertEqual(code,status);XCTAssertFalse((200..<300).contains(status))}
            catch BackendAPIError.invalidResponse {XCTAssertTrue([201,204].contains(status))}
            catch {XCTFail()}
        }
        for payload in [Data("not JSON".utf8),try JSONSerialization.data(withJSONObject:summary())+Data(repeating:32,count:4*1024*1024)] {
            api.replies.append(.init(status:200,body:payload))
            do {_ = try await service.apply(.remove(bindingID:"1"),to:row,snapshot:old);XCTFail()}catch {}
        }
        let count=api.calls.count;try add(api);api.cancel=true
        let task=Task {@MainActor in try await service.apply(.remove(bindingID:"1"),to:row,snapshot:old)}
        do {_ = try await task.value;XCTFail()}catch is CancellationError {}catch {XCTFail()}
        XCTAssertEqual(api.calls.count,count+1)
    }
}
