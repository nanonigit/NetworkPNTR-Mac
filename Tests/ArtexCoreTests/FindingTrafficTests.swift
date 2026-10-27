import CryptoKit
import XCTest
@testable import ArtexCore

@MainActor private final class TrafficReadAPI: BackendJSONTransport {
    var replies: [BackendHTTPResponse] = []
    var paths: [String] = []
    var cancel = false
    func send(method: String,path: String,body: Data?,bearer: String?) async throws -> BackendHTTPResponse {
        XCTAssertEqual(method,"GET"); XCTAssertNil(body); XCTAssertNil(bearer); paths.append(path)
        if cancel { withUnsafeCurrentTask { $0?.cancel() } }
        guard !replies.isEmpty else { throw BackendAPIError.invalidResponse }; return replies.removeFirst()
    }
    func add(_ value: Any,status: Int = 200) throws {
        replies.append(.init(status:status,body:try JSONSerialization.data(withJSONObject:value,options:[.sortedKeys])))
    }
}
final class FindingTrafficTests: XCTestCase {
    private func binding() throws -> [String:Any] {
        let url = try XCTUnwrap(Bundle.module.url(forResource:"Fixtures/findings-traffic-contract",withExtension:"json"))
        let value = try XCTUnwrap(JSONSerialization.jsonObject(with:Data(contentsOf:url)) as? [String:Any])
        var binding = try XCTUnwrap(value["binding"] as? [String:Any])
        binding["note"] = "\u{feff}e\u{301} 中文 한국어"
        return binding
    }
    private func decode<T: Decodable>(_ type: T.Type,_ value: Any) throws -> T {
        try BackendJSONCoding.decode(type,from:JSONSerialization.data(withJSONObject:value))
    }
    private func preview(offset: Int64 = 0,total: Int64 = 9000,next: Int64 = 8191,binary: Bool = false) -> [String:Any] {
        ["content":binary ? "[binary display]" : "\u{feff}e\u{301} 中文 한국어", "offset":offset,"total":total,"next_offset":next,"truncated":next<total,"binary":binary]
    }
    func testPinnedContractHashesAndRawCustomMetadata() throws {
        let fixture = try XCTUnwrap(Bundle.module.url(forResource:"Fixtures/findings-traffic-contract",withExtension:"json"))
        let value = try XCTUnwrap(JSONSerialization.jsonObject(with:Data(contentsOf:fixture)) as? [String:Any])
        XCTAssertEqual(value["source_commit"] as? String,"e75ae371ad777ffd1eecdd28d2781a6519b05591")
        let hashes = try XCTUnwrap(value["source_hashes"] as? [String:String]); XCTAssertEqual(hashes.count,4)
        let root = URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("artex-local/source")
        for (path,hash) in hashes {
            XCTAssertEqual(hash.count,64);XCTAssertTrue(hash.utf8.allSatisfy{(48...57).contains($0)||(97...102).contains($0)})
            if FileManager.default.fileExists(atPath:root.path) {
                let bytes = try Data(contentsOf:root.appendingPathComponent(path))
                XCTAssertEqual(SHA256.hash(data:bytes).map{String(format:"%02x",$0)}.joined(),hash)
            }
        }
        let row = try decode(FindingTrafficBinding.self,binding())
        XCTAssertEqual(row.id,"9007199254740993"); XCTAssertEqual(row.role,"future-role")
        XCTAssertEqual(Array(row.note.utf8),Array("\u{feff}e\u{301} 中文 한국어".utf8))
        XCTAssertEqual(row.snapshot.sourceTrafficId,"opaque/source+id"); XCTAssertEqual(row.snapshot.requestLength,0)
        XCTAssertEqual(row.snapshot.responseLength,9000)
    }
    func testSummaryIdentityNullEmptyAndDuplicateRules() throws {
        let row = try binding()
        let good: [String:Any] = ["finding_id":"9101","version":2,"report_version":1,"bindings":[row]]
        let result = try decode(FindingTraffic.self,good); XCTAssertEqual(result.bindings.count,1)
        for v: Any in [[],NSNull()] {
            var value=good;value["bindings"]=v;XCTAssertTrue(try decode(FindingTraffic.self,value).bindings.isEmpty)
        }
        for key in ["finding_id","version","report_version","bindings"] {
            var value=good;value.removeValue(forKey:key);XCTAssertThrowsError(try decode(FindingTraffic.self,value))
        }
        for (key,v): (String,Any) in [("finding_id","99"),("version",-1),("report_version",-1),("bindings",[row,row])] {
            var value=good;value[key]=v;XCTAssertThrowsError(try decode(FindingTraffic.self,value))
        }
        for (key,v): (String,Any) in [("id","0"),("finding_id","01"),("snapshot_id","different"),("position",-1)] {
            var value=row;value[key]=v;XCTAssertThrowsError(try decode(FindingTrafficBinding.self,value))
        }
        for key in ["req_len","resp_len"] {
            var value=row,snapshot=try XCTUnwrap(row["snapshot"] as? [String:Any]);snapshot[key] = -1;value["snapshot"]=snapshot
            XCTAssertThrowsError(try decode(FindingTrafficBinding.self,value))
        }
        var summaryRow=row,snapshot=try XCTUnwrap(row["snapshot"] as? [String:Any])
        snapshot.removeValue(forKey:"req_head");snapshot.removeValue(forKey:"resp_head");summaryRow["snapshot"]=snapshot
        let summaryBinding=try decode(FindingTrafficBinding.self,summaryRow)
        XCTAssertEqual(summaryBinding.snapshot.requestHead,"");XCTAssertEqual(summaryBinding.snapshot.responseHead,"")
        for key in ["id","source_traffic_id"] {
            var invalid=snapshot;invalid[key]="";summaryRow["snapshot"]=invalid
            XCTAssertThrowsError(try decode(FindingTrafficBinding.self,summaryRow))
        }
    }
    func testPreviewUsesBytesNotContentLengthAndRejectsInvalidProgress() throws {
        for binary in [false,true] {
            let value = try decode(FindingEvidencePreview.self,preview(binary:binary))
            XCTAssertEqual(value.nextOffset,8191);XCTAssertEqual(value.binary,binary)
        }
        var end=preview(offset:9000,total:9000,next:9000);end["content"]=""
        XCTAssertFalse(try decode(FindingEvidencePreview.self,end).truncated)
        for (key,v): (String,Any) in [("offset",-1),("total",-1),("next_offset",9001),("next_offset",0),("truncated",false)] {
            var value=preview();value[key]=v;XCTAssertThrowsError(try decode(FindingEvidencePreview.self,value))
        }
        XCTAssertThrowsError(try decode(FindingEvidencePreview.self,preview(total:90000,next:8193)))
        var overflow=preview();overflow["next_offset"]=UInt64.max
        XCTAssertThrowsError(try decode(FindingEvidencePreview.self,overflow))
        for key in ["content","offset","total","next_offset","truncated","binary"] {
            var value=preview();value.removeValue(forKey:key)
            XCTAssertThrowsError(try decode(FindingEvidencePreview.self,value))
        }
        XCTAssertThrowsError(try decode(FindingEvidencePreview.self,preview(offset:2,total:3,next:1)))
    }
    @MainActor func testThreeReadRoutesBindExactOwnerContextBindingAndByteOffset() async throws {
        let api=TrafficReadAPI(),service=FindingTrafficService(client:api),row=try binding()
        try api.add(["finding_id":"9101","version":1,"report_version":0,"bindings":[row]])
        let summary=try await service.list(findingID:"09101",contextTaskID:"8111")
        XCTAssertEqual(summary.findingId,"9101");XCTAssertEqual(api.paths.last,"/api/exploration/findings/9101/traffic?context_task=8111")
        let empty: [String:Any] = ["content":"","offset":0,"total":0,"next_offset":0,"truncated":false,"binary":false]
        try api.add(["binding":row,"request":empty,"response":preview()])
        let detail=try await service.detail(findingID:"9101",bindingID:"9007199254740993",contextTaskID:"8111")
        XCTAssertEqual(detail.binding.id,"9007199254740993")
        XCTAssertEqual(api.paths.last,"/api/exploration/findings/9101/traffic/9007199254740993?context_task=8111")
        try api.add(preview(offset:8191,next:9000))
        let page=try await service.body(findingID:"9101",bindingID:"9007199254740993",side:.response,offset:8191,contextTaskID:"8111")
        XCTAssertEqual(page.offset,8191)
        XCTAssertEqual(api.paths.last,"/api/exploration/findings/9101/traffic/9007199254740993/body?side=response&offset=8191&context_task=8111")
    }
    @MainActor func testInvalidInputsAndMismatchedRepliesCannotCrossOwnersOrOffsets() async throws {
        let api=TrafficReadAPI(),service=FindingTrafficService(client:api)
        let cancelled=Task { @MainActor in
            withUnsafeCurrentTask { $0?.cancel() }
            return try await service.list(findingID:"9101")
        }
        do {_ = try await cancelled.value;XCTFail()}catch is CancellationError {}catch {XCTFail("wrong preflight cancellation")}
        XCTAssertTrue(api.paths.isEmpty)
        for id in ["0","../1","9223372036854775808",""] {
            do {_ = try await service.list(findingID:id);XCTFail()}catch {}
            do {_ = try await service.detail(findingID:"9101",bindingID:id);XCTFail()}catch {}
            do {_ = try await service.list(findingID:"9101",contextTaskID:id);XCTFail()}catch {}
        }
        do {_ = try await service.body(findingID:"9101",bindingID:"1",side:.request,offset:-1);XCTFail()}catch {}
        XCTAssertTrue(api.paths.isEmpty)
        try api.add(["finding_id":"99","version":0,"report_version":0,"bindings":[]])
        do {_ = try await service.list(findingID:"9101");XCTFail()}catch {}
        try api.add(preview())
        do {_ = try await service.body(findingID:"9101",bindingID:"1",side:.request,offset:4);XCTFail()}catch {}
        let row=try binding(),empty: [String:Any]=["content":"","offset":0,"total":0,"next_offset":0,"truncated":false,"binary":false]
        for (owner,bid) in [("99","9007199254740993"),("9101","1")] {
            try api.add(["binding":row,"request":empty,"response":preview()])
            do {_ = try await service.detail(findingID:owner,bindingID:bid);XCTFail()}catch {}
        }
        try api.add(["binding":row,"request":preview(),"response":preview()])
        do {_ = try await service.detail(findingID:"9101",bindingID:"9007199254740993");XCTFail()}catch {}
    }
    @MainActor func testStatusMalformedOversizeAndCancellationNeverRetry() async throws {
        let api=TrafficReadAPI(),service=FindingTrafficService(client:api)
        for status in [201,204,302,401,404,409,422,500] {
            try api.add(["error":"private server text"],status:status)
            do {_ = try await service.list(findingID:"9101");XCTFail()}catch {}
        }
        for body in [Data("not JSON".utf8),Data(repeating:32,count:4*1024*1024+1)] {
            api.replies.append(.init(status:200,body:body));do {_ = try await service.list(findingID:"9101");XCTFail()}catch {}
        }
        let count=api.paths.count
        try api.add(["finding_id":"9101","version":0,"report_version":0,"bindings":[]]);api.cancel=true
        let task=Task {@MainActor in try await service.list(findingID:"9101")}
        do {_ = try await task.value;XCTFail()}catch is CancellationError {}catch {XCTFail("wrong cancellation")}
        XCTAssertEqual(api.paths.count,count+1)
    }
}
