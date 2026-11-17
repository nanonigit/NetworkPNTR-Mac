import Foundation
import XCTest
@testable import NetworkPNTRCore

@MainActor private final class TrafficAPI: BackendJSONTransport {
    var calls:[(String,String,Data?)]=[]
    var reply=BackendHTTPResponse(status:200,body:Data())
    var cancel=false
    func send(method:String,path:String,body:Data?,bearer:String?) async throws -> BackendHTTPResponse {
        XCTAssertNil(bearer);calls.append((method,path,body));if cancel {withUnsafeCurrentTask{$0?.cancel()}};return reply
    }
    func set(_ value:Any,status:Int=200) throws {reply = .init(status:status,body:try JSONSerialization.data(withJSONObject:value))}
}
final class TrafficServiceTests:XCTestCase {
    // Decode percent bytes independently; Foundation's String decoding can consume a leading UTF8 BOM.
    private func queryBytes(_ path: String) throws -> [String: Data] {
        let components = try XCTUnwrap(URLComponents(string: path))
        let query = try XCTUnwrap(components.percentEncodedQuery)
        var result: [String: Data] = [:]
        for item in query.split(separator: "&") {
            let pair = item.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            XCTAssertEqual(pair.count, 2)
            let raw = Array(pair[1].utf8)
            var decoded = Data(), cursor = 0
            while cursor < raw.count {
                if raw[cursor] == 37 {
                    XCTAssertLessThan(cursor + 2, raw.count)
                    let hex = String(decoding: raw[(cursor + 1)...(cursor + 2)], as: UTF8.self)
                    decoded.append(try XCTUnwrap(UInt8(hex, radix: 16))); cursor += 3
                } else {
                    XCTAssertNotEqual(raw[cursor], 43, "A literal plus would become a space in the Go server")
                    decoded.append(raw[cursor]); cursor += 1
                }
            }
            result[String(pair[0])] = decoded
        }
        return result
    }

    func testAllQueryFieldsEncodeAsDataAndPreserveExactIntegerBounds() throws {
        var query=TrafficQuery();query.page=2;query.size=200;query.host="\u{FEFF}e\u{301}&h+";query.keyword="a+b&x=?";query.body="中";query.path="/api?q=1";query.method = .post;query.status = .exact(404);query.responseMinimum=9007199254740993;query.responseMaximum=Int64.max;query.sort = .responseLength;query.order = .ascending
        let path=try query.pathString();XCTAssertTrue(path.hasPrefix("/api/traffic?"))
        let fields=try queryBytes(path)
        XCTAssertEqual(fields,["page":"2","size":"200","host":query.host,"q":query.keyword,"body":"中","path":"/api?q=1","method":"POST","status":"404","resp_min":"9007199254740993","resp_max":String(Int64.max),"sort":"resp_len","order":"asc"].mapValues{Data($0.utf8)})
        XCTAssertEqual(try XCTUnwrap(fields["host"]),Data(query.host.utf8))
    }
    func testQueryDefaultsBucketsInvertedRangeAndBoundaryFailures() throws {
        let query=TrafficQuery();XCTAssertEqual(try query.pathString(),"/api/traffic?page=0&size=50&sort=ts&order=desc")
        var filtered=query;filtered.status = .serverError;filtered.responseMinimum=20;filtered.responseMaximum=10
        XCTAssertTrue(try filtered.pathString().contains("status=5xx"));XCTAssertTrue(try filtered.pathString().contains("resp_min=20"))
        for mode in 0..<6 {
            var bad=query
            switch mode {case 0:bad.page = -1;case 1:bad.size=501;case 2:bad.page=Int64.max;case 3:bad.responseMinimum = -1;case 4:bad.body=String(repeating:"x",count:8193);default:bad.path=String(repeating:"&",count:4096)}
            XCTAssertThrowsError(try bad.pathString())
        }
    }
    func testHostNullCountsByteIdentityAndMalformedData() throws {
        let empty=try BackendJSONCoding.decode(TrafficHosts.self,from:Data(#"{"hosts":null}"#.utf8));XCTAssertTrue(empty.hosts.isEmpty)
        let names=["é","e\u{301}","\u{FEFF}host"]
        let bytes=try JSONSerialization.data(withJSONObject:["hosts":names.map{["host":$0,"count":9007199254740993] as [String:Any]}])
        let result=try BackendJSONCoding.decode(TrafficHosts.self,from:bytes);XCTAssertEqual(result.hosts.count,3);XCTAssertEqual(result.hosts[0].count,9007199254740993);XCTAssertEqual(Set(result.hosts.map(\.identity)).count,3)
        for value:Any in [[:],["hosts":[["host":"a","count":-1]]],["hosts":[["host":"a","count":1],["host":"a","count":2]]]] {XCTAssertThrowsError(try BackendJSONCoding.decode(TrafficHosts.self,from:JSONSerialization.data(withJSONObject:value)))}
    }
    @MainActor func testReadRoutesProxyAndNullHostCompatibility() async throws {
        let api=TrafficAPI(),service=TrafficService(client:api)
        try api.set(["enabled":false,"proxy":"127.0.0.1:8788","count":0,"total":0,"page":0,"size":50,"exchanges":[]]);let page=try await service.list();XCTAssertEqual(page.proxy,"127.0.0.1:8788");XCTAssertFalse(page.isUnavailable)
        try api.set(["hosts":NSNull()]);let hosts=try await service.hosts();XCTAssertTrue(hosts.hosts.isEmpty)
        try api.set(["traffic_capture":false,"workers":123]);let settings=try await service.captureSettings();XCTAssertFalse(settings.trafficCapture)
        try api.set(["req":"\u{FEFF}中文 한국어","resp":"raw"]);let detail=try await service.detail(id:"a+b&x");XCTAssertEqual(Data(detail.request.utf8),Data("\u{FEFF}中文 한국어".utf8))
        XCTAssertEqual(api.calls.map{$0.0},["GET","GET","GET","GET"]);XCTAssertEqual(api.calls[0].1,"/api/traffic?page=0&size=50&sort=ts&order=desc");XCTAssertEqual(api.calls[1].1,"/api/traffic/hosts");XCTAssertEqual(api.calls[2].1,"/api/settings")
        XCTAssertEqual(URLComponents(string:api.calls[3].1)?.queryItems?.first?.value,"a+b&x")
    }
    @MainActor func testMutationScopesFixedRoutesAndPartialSettingBody() async throws {
        let api=TrafficAPI(),service=TrafficService(client:api);var dispatched=0
        try api.set(["deleted":9007199254740993]);let filter=try await service.apply(.deleteMatchingHost("api&x+"),onDispatch:{dispatched+=1})
        guard case .deleted(let receipt)=filter else {return XCTFail("Deletion")};XCTAssertEqual(receipt.deleted,9007199254740993)
        let names=[" api ","\u{FEFF}host","api","api",""]
        _ = try await service.apply(.deleteHosts(names))
        struct SentHosts:Decodable {let hosts:[String]}
        let sentHosts=try BackendJSONCoding.decode(SentHosts.self,from:XCTUnwrap(api.calls[1].2))
        XCTAssertEqual(sentHosts.hosts.map{Data($0.utf8)},names.map{Data($0.utf8)})
        try api.set(["deleted":1,"reclaimed":Int64.max]);_ = try await service.apply(.purgeAll)
        try api.set(["traffic_capture":true,"workers":99]);let capture=try await service.apply(.capture(true));guard case .capture(let settings)=capture else {return XCTFail("Capture")};XCTAssertTrue(settings.trafficCapture)
        XCTAssertEqual(api.calls.map{$0.0},["DELETE","DELETE","DELETE","PUT"]);XCTAssertEqual(api.calls[1].1,"/api/traffic/hosts");XCTAssertEqual(api.calls[2].1,"/api/traffic/all");XCTAssertEqual(api.calls[3].1,"/api/settings")
        let sent=try XCTUnwrap(JSONSerialization.jsonObject(with:XCTUnwrap(api.calls[3].2)) as? [String:Bool]);XCTAssertEqual(sent,["traffic_capture":true]);XCTAssertEqual(dispatched,1)
        XCTAssertEqual(URLComponents(string:api.calls[0].1)?.queryItems?.first?.value,"api&x+")
    }
    @MainActor func testFEFFOnlyHostsUseGoSpaceRulesAndRemainExactWireBytes() async throws {
        let api=TrafficAPI(),service=TrafficService(client:api);try api.set(["deleted":0])
        _ = try await service.apply(.deleteMatchingHost("\u{FEFF}"))
        XCTAssertEqual(try queryBytes(api.calls[0].1)["host"],Data([0xef,0xbb,0xbf]))
        _ = try await service.apply(.deleteHosts(["\u{FEFF}"]))
        struct Sent:Decodable {let hosts:[String]}
        let sent=try BackendJSONCoding.decode(Sent.self,from:XCTUnwrap(api.calls[1].2));XCTAssertEqual(sent.hosts.map{Data($0.utf8)},[Data([0xef,0xbb,0xbf])]);XCTAssertEqual(api.calls.count,2)
    }
    @MainActor func testPageEchoMismatchAndUnavailableRemainDistinctAndInvalidQueryDoesNotDispatch() async throws {
        let api=TrafficAPI(),service=TrafficService(client:api)
        for (page,size) in [(1,50),(0,25)] {
            try api.set(["enabled":false,"count":0,"total":0,"page":page,"size":size,"exchanges":[]])
            do{_ = try await service.list();XCTFail("Wrong page echo")}catch{}
        }
        try api.set(["enabled":false,"exchanges":[]]);let missing=try await service.list();XCTAssertTrue(missing.isUnavailable)
        let calls=api.calls.count;var bad=TrafficQuery();bad.page = -1
        do{_ = try await service.list(bad);XCTFail("Invalid query")}catch{}
        XCTAssertEqual(api.calls.count,calls)
    }
    @MainActor func testInvalidWritesNeverDispatchAndCallbackCanRejectBeforeTransport() async throws {
        let api=TrafficAPI(),service=TrafficService(client:api)
        for change:TrafficMutation in [.deleteMatchingHost(" \n"),.deleteHosts([]),.deleteHosts([" ","\u{85}"]),.deleteMatchingHost(String(repeating:"x",count:8193))] {
            do {_ = try await service.apply(change,onDispatch:{XCTFail("Invalid dispatch")});XCTFail("Invalid accepted")}catch{}
        }
        do {_ = try await service.apply(.purgeAll,onDispatch:{throw CancellationError()});XCTFail("Rejected dispatch")}catch{XCTAssertTrue(error is CancellationError)}
        XCTAssertTrue(api.calls.isEmpty)
    }
    @MainActor func testInvalidPurgeReceiptsAndCaptureMismatchRemainUnconfirmedErrors() async throws {
        let api=TrafficAPI(),service=TrafficService(client:api)
        for value:Any in [["deleted":1],["deleted":-1,"reclaimed":0],["deleted":1,"reclaimed":-1],[:]] {
            try api.set(value);do{_ = try await service.apply(.purgeAll);XCTFail("Bad purge")}catch{}
        }
        try api.set(["traffic_capture":false]);do{_ = try await service.apply(.capture(true));XCTFail("Wrong capture")}catch{}
        XCTAssertEqual(api.calls.count,5)
    }
    @MainActor func testValidOversizedHostRequestNeverDispatchesAndPostDispatchCancelDoesNotReplay() async throws {
        let api=TrafficAPI(),service=TrafficService(client:api)
        let hosts=Array(repeating:String(repeating:"h",count:8192),count:129)
        do{_ = try await service.apply(.deleteHosts(hosts),onDispatch:{XCTFail("Oversized dispatch")});XCTFail("Oversized request")}catch{}
        XCTAssertTrue(api.calls.isEmpty)
        try api.set(["deleted":0,"reclaimed":0]);api.cancel=true;var callbacks=0
        let job=Task{try await service.apply(.purgeAll,onDispatch:{callbacks+=1})}
        do{_ = try await job.value;XCTFail("Cancelled after dispatch")}catch{XCTAssertTrue(error is CancellationError)}
        XCTAssertEqual(callbacks,1);XCTAssertEqual(api.calls.count,1)
    }
    func testAllTypedStatusAndSortValuesAndOptionalProxyWireShapes() throws {
        let statuses:[TrafficStatusFilter]=[.informational,.success,.redirect,.clientError,.serverError,.exact(-1)]
        for (value,wire) in zip(statuses,["1xx","2xx","3xx","4xx","5xx","-1"]) {
            var query=TrafficQuery();query.status=value;XCTAssertEqual(try queryBytes(query.pathString())["status"],Data(wire.utf8))
        }
        for sort in TrafficSort.allCases {var query=TrafficQuery();query.sort=sort;XCTAssertEqual(try queryBytes(query.pathString())["sort"],Data(sort.rawValue.utf8))}
        for value:Any in [["enabled":false,"exchanges":[]],["enabled":false,"proxy":NSNull(),"exchanges":[]]] {
            let result=try BackendJSONCoding.decode(CapturedTrafficPage.self,from:JSONSerialization.data(withJSONObject:value));XCTAssertNil(result.proxy);XCTAssertTrue(result.isUnavailable)
        }
    }
    @MainActor func testReadAndMutationStatusShapeSizeAndCancellationBounds() async throws {
        let api=TrafficAPI(),service=TrafficService(client:api)
        for mode in 0..<4 {
            switch mode {
            case 0:try api.set(["hosts":[]],status:500)
            case 1:try api.set(["wrong":[]])
            case 2:try api.set(["hosts":[]]);var bytes=api.reply.body;bytes.append(Data(repeating:32,count:4*1024*1024+1-bytes.count));_ = try JSONSerialization.jsonObject(with:bytes);api.reply = .init(status:200,body:bytes)
            default:try api.set(["hosts":[]]);api.cancel=true
            }
            do{_ = try await service.hosts();XCTFail("Bad read")}catch{}
        }
        let fresh=TrafficAPI(),other=TrafficService(client:fresh);let job=Task{try await other.apply(.purgeAll)};job.cancel();do{_ = try await job.value;XCTFail("Cancelled")}catch{XCTAssertTrue(error is CancellationError)};XCTAssertTrue(fresh.calls.isEmpty)
    }
}
