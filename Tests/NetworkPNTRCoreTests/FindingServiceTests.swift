import XCTest
@testable import NetworkPNTRCore

@MainActor private final class FindingAPI: BackendJSONTransport {
    var replies: [BackendHTTPResponse] = []
    var calls: [(String,String,Data?)] = []
    var cancel = false
    func send(method: String,path: String,body: Data?,bearer: String?) async throws -> BackendHTTPResponse {
        calls.append((method,path,body)); if cancel { withUnsafeCurrentTask{$0?.cancel()} }
        guard !replies.isEmpty else { throw BackendAPIError.invalidResponse }; return replies.removeFirst()
    }
    func add(_ json: String,status: Int = 200) { replies.append(.init(status:status,body:Data(json.utf8))) }
}
final class FindingServiceTests: XCTestCase {
    private let large = "9007199254740993"
    private func record(_ overrides: [String:Any] = [:], removing: [String] = []) throws -> String {
        let path = try XCTUnwrap(Bundle.module.url(forResource:"Fixtures/findings-contract",withExtension:"json"))
        let wrapper = try XCTUnwrap(JSONSerialization.jsonObject(with:Data(contentsOf:path)) as? [String:Any])
        var value = try XCTUnwrap(wrapper["record"] as? [String:Any])
        // Reinsert the leading FEFF value because JSONSerialization may strip it from decoded strings.
        value["name"] = "\u{feff}e\u{301} 中文 한국어"
        value.merge(overrides,uniquingKeysWith:{$1}); for key in removing { value.removeValue(forKey:key) }
        return String(decoding:try JSONSerialization.data(withJSONObject:value,options:[.sortedKeys]),as:UTF8.self)
    }
    private func decode(_ text: String) throws -> FindingRecord { try BackendJSONCoding.decode(FindingRecord.self,from:Data(text.utf8)) }
    private func page(_ rows: [String],page: Int64 = 1,size: Int = 20,total: Int64? = nil) -> String {
        "{\"items\":["+rows.joined(separator:",")+"],\"total\":\(total ?? Int64(rows.count)),\"page\":\(page),\"page_size\":\(size)}"
    }
    func testRecordPreservesExactUnicodeLargeCountersAndOptionalFields() throws {
        let row = try decode(record()); XCTAssertEqual(row.id,large); XCTAssertEqual(row.findingId,large)
        XCTAssertEqual(Array(row.name.utf8),Array("\u{feff}e\u{301} 中文 한국어".utf8)); XCTAssertEqual(row.evidenceVersion,9007199254740993)
        XCTAssertEqual(row.assets.first?.id,"9007199254740997"); XCTAssertTrue(row.reportStale); XCTAssertTrue(row.canMutate)
        let future = try decode(record(["severity":"future 中文","status":"future 한국어"],removing:["name","assets","report","finding_id","traffic_count","evidence_version","report_evidence_version","report_stale"]))
        XCTAssertEqual(future.name,""); XCTAssertTrue(future.assets.isEmpty); XCTAssertEqual(future.report,""); XCTAssertEqual(future.trafficCount,0); XCTAssertFalse(future.canMutate)
    }
    func testMalformedRecordIDsCountsAndProvenanceAreRejected() throws {
        for (key,value): (String,Any) in [("id","../7"),("finding_id","0"),("task_id","01"),("traffic_count",-1),("evidence_version",-1),("report_stale","true"),("assets",[["id":"0","type":"x","label":"raw"]]) ] {
            XCTAssertThrowsError(try decode(record([key:value])),"accepted \(key)")
        }
        XCTAssertThrowsError(try decode(record(["inherited":true])))
        let inherited = try decode(record(["id":"41","inherited":true,"source_task_id":"9007199254740995"]))
        XCTAssertFalse(inherited.canMutate); XCTAssertEqual(inherited.id,"41"); XCTAssertEqual(inherited.findingId,large)
    }
    @MainActor func testFlatQueryUsesTaskIDAndEscapesOnceWithBrowserSearchTrim() async throws {
        let api = FindingAPI(); api.add(page([try record()],page:2,size:50,total:101))
        let query = FindingQuery(page:2,size:50,severity:.high,status:.riskAccepted,vulnclass:"CWE+中文",task:"__unassigned__",search:"\u{feff} e\u{301} +&= 한국어 \u{feff}",sort:.time,assetScope:"r:e\u{301}+&")
        let result = try await FindingService(client:api).list(query)
        XCTAssertEqual(result.total,101); let components = try XCTUnwrap(URLComponents(string:api.calls[0].1)); let params = Dictionary(uniqueKeysWithValues:(components.queryItems ?? []).map{($0.name,$0.value ?? "")})
        XCTAssertEqual(components.path,"/api/exploration/findings"); XCTAssertNil(params["task"]); XCTAssertEqual(params["task_id"],"__unassigned__")
        XCTAssertEqual(params["q"],"e\u{301} +&= 한국어"); XCTAssertEqual(params["asset_scope"],"r:e\u{301}+&"); XCTAssertEqual(params["severity"],"high"); XCTAssertEqual(params["status"],"risk_accepted")
        XCTAssertTrue(api.calls[0].1.contains("%2B")); XCTAssertEqual(params["limit"],"50")
    }
    @MainActor func testInvalidQueryNeverDispatchesAndPageIdentityCannotLie() async throws {
        let api = FindingAPI(), service = FindingService(client:api)
        for query in [FindingQuery(page:0),FindingQuery(size:201),FindingQuery(page:Int64.max,size:2),FindingQuery(task:"../../1"),FindingQuery(search:String(repeating:"x",count:8193))] {
            do { _ = try await service.list(query); XCTFail("invalid query dispatched") } catch {}
        }
        XCTAssertTrue(api.calls.isEmpty)
        for response in [page([],page:2),page([try record(),try record()]),"{\"items\":null,\"page\":1,\"page_size\":20,\"total\":-1}","{\"page\":1,\"page_size\":20,\"total\":0}"] {
            api.add(response); do { _ = try await service.list(); XCTFail("invalid page accepted") } catch {}
        }
        api.add("{\"items\":null,\"page\":1,\"page_size\":20,\"total\":0}"); let empty = try await service.list(); XCTAssertTrue(empty.items.isEmpty)
    }
    @MainActor func testGlobalAndDetailUseStandaloneIdentityAndExplicitContext() async throws {
        let api = FindingAPI(), service = FindingService(client:api)
        api.add(try record(["id":"41"])); do { _ = try await service.list(); XCTFail("bare record page accepted") } catch {}
        api.add(page([try record(["id":"41"])])); do { _ = try await service.list(); XCTFail("node handle accepted globally") } catch {}
        api.add(try record(["id":"41"])); do { _ = try await service.detail(id:large); XCTFail("wrong detail owner") } catch {}
        api.add(try record(["inherited":true,"source_task_id":"9007199254740995"]))
        let row = try await service.detail(id:large,contextTaskID:"99"); XCTAssertTrue(row.inherited); XCTAssertEqual(api.calls.last?.1,"/api/exploration/findings/\(large)?context_task=99")
        api.add(try record()); do { _ = try await service.detail(id:large,contextTaskID:"99"); XCTFail("unrelated context accepted") } catch {}
    }
    @MainActor func testPerTaskBareArrayPreservesLegacyAndInheritedNodeIdentity() async throws {
        let api = FindingAPI(), service = FindingService(client:api)
        api.add("[" + (try record(["id":"41","inherited":true,"source_task_id":"9007199254740995"])) + "," + (try record(["id":"41","task_id":"99"],removing:["finding_id"])) + "]")
        let rows = try await service.forTask(id:"99"); XCTAssertEqual(rows.count,2); XCTAssertTrue(rows.allSatisfy{!$0.canMutate})
        XCTAssertEqual(api.calls[0].1,"/api/exploration/findings?task=99")
        api.add("null"); let empty = try await service.forTask(id:"99"); XCTAssertTrue(empty.isEmpty)
        api.add("["+(try record())+"]"); do { _ = try await service.forTask(id:"99"); XCTFail("unrelated task row accepted") } catch {}
    }
    @MainActor func testPatchOmissionEmptyFieldsStandaloneHandleAndServerTrim() async throws {
        let api = FindingAPI(), service = FindingService(client:api), target = try decode(record(["id":"41"]))
        api.add(try record(["name":"e\u{301} 中文","vulnclass":"","status":"confirmed"]))
        let row = try await service.update(target,patch:FindingPatch(name:"\u{feff}\u{85}e\u{301} 中文\u{85}\u{feff}",vulnclass:" \u{feff}",status:.confirmed))
        XCTAssertEqual(row.id,large); XCTAssertEqual(api.calls[0].1,"/api/exploration/findings/\(large)")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with:XCTUnwrap(api.calls[0].2)) as? [String:Any]); XCTAssertEqual(Set(body.keys),["name","vulnclass","status"])
        XCTAssertEqual(body["name"] as? String,"\u{85}e\u{301} 中文\u{85}"); XCTAssertEqual(body["vulnclass"] as? String,"")
        api.add(try record(["status":"confirmed"])); do { _ = try await service.update(target,patch:.init(severity:.critical)); XCTFail("wrong confirmed field") } catch {}
        do { _ = try await service.update(target,patch:.init()); XCTFail("empty patch") } catch {}
        XCTAssertEqual(api.calls.count,2)
    }
    @MainActor func testReadOnlyRowsAndInvalidHandlesCannotWriteAndDeleteNeedsExactReceipt() async throws {
        let api = FindingAPI(), service = FindingService(client:api)
        let inherited = try decode(record(["inherited":true,"source_task_id":"9007199254740995"]))
        let legacy = try decode(record(removing:["finding_id"]))
        for target in [inherited,legacy] {
            do { _ = try await service.update(target,patch:.init(status:.fixed)); XCTFail("read-only updated") } catch {}
            do { _ = try await service.delete(target); XCTFail("read-only deleted") } catch {}
        }
        XCTAssertTrue(api.calls.isEmpty); let target = try decode(record())
        for json in ["{\"deleted\":false,\"id\":\(large)}","{\"deleted\":true,\"id\":7}","{\"deleted\":true,\"id\":\"\(large)\"}"] {
            api.add(json); do { _ = try await service.delete(target); XCTFail("bad deletion receipt") } catch {}
        }
        api.add("{\"deleted\":true,\"id\":\(large)}"); let receipt = try await service.delete(target); XCTAssertEqual(receipt.id,9007199254740993)
    }
    @MainActor func testUnexpectedSuccessStatusErrorBodyLimitsAndCancellationCannotConfirm() async throws {
        let api = FindingAPI(), service = FindingService(client:api)
        for status in [201,202,204,400,500] {
            api.add(try record(),status:status); do { _ = try await service.detail(id:large); XCTFail("status accepted") } catch {}
        }
        api.add(try record() + String(repeating:" ",count:4*1024*1024)); do { _ = try await service.detail(id:large); XCTFail("oversize response") } catch {}
        let target = try decode(record()); do { _ = try await service.update(target,patch:.init(name:String(repeating:"x",count:65537))); XCTFail("oversize write") } catch {}
        let calls = api.calls.count; api.cancel = true; api.add(try record())
        let operation = Task { try await service.detail(id:large) }; do { _ = try await operation.value; XCTFail("post dispatch cancellation") } catch {}
        XCTAssertEqual(api.calls.count,calls+1)
        let cancelled = Task { withUnsafeCurrentTask{$0?.cancel()}; return try await service.detail(id:self.large) }
        do { _ = try await cancelled.value; XCTFail("precancelled read") } catch {}
        XCTAssertEqual(api.calls.count,calls+1)
    }
    func testKnownWriteEnumsAndSafeBilingualValidation() {
        XCTAssertEqual(FindingStatus.allCases.count,9); XCTAssertEqual(FindingSeverity.allCases.count,4)
        for language in AppLanguage.allCases {
            for error in [FindingInputError.invalidID,.query,.patch,.readOnly,.bodyLimit] {
                let text = AppErrorMessage(error).text(language:language); XCTAssertEqual(text,AppStrings.text(error.key,language:language)); XCTAssertFalse(text.isEmpty); XCTAssertFalse(text.contains("中文")); XCTAssertFalse(text.contains("한국어"))
            }
        }
    }
}

extension FindingServiceTests {
    private var groupJSON: String { #"{"task_id":9007199254740995,"task_name":"é 中文 한국어","task_description":"literal","task_status":"future","count":2,"critical":0,"high":2,"medium":0,"low":0,"last_found_at":"2026-10-22T12:00:00Z"}"# }
    private var treeJSON: String { #"{"nodes":[{"key":"c:1","kind":"company","label":"é 中文 한국어","company_id":1,"self":0,"total":1,"critical":0,"high":1,"medium":0,"low":0,"last_found_at":"raw"},{"key":"a:2","parent":"c:1","kind":"future","label":"literal","asset_id":2,"self":1,"total":1,"critical":0,"high":1,"medium":0,"low":0,"last_found_at":"raw"}],"finding_total":1,"truncated":false,"dropped_kinds":[]}"# }
    @MainActor func testGroupsExactNumericOrStringIDsAndIndependentPagination() async throws {
        let api = FindingAPI(), service = FindingService(client:api)
        for group in [groupJSON,groupJSON.replacingOccurrences(of:"9007199254740995",with:"\"9007199254740995\"")] {
            api.add("{\"items\":["+group+"],\"total\":1,\"finding_total\":2,\"page\":3,\"page_size\":10}")
            let result = try await service.groups(.init(page:3,size:10)); XCTAssertEqual(result.items[0].taskId,"9007199254740995"); XCTAssertEqual(result.findingTotal,2)
            XCTAssertTrue(api.calls.last!.1.contains("/groups?")); XCTAssertTrue(api.calls.last!.1.contains("limit=10"))
        }
        api.add("{\"items\":["+groupJSON.replacingOccurrences(of:"9007199254740995",with:"null")+"],\"total\":1,\"finding_total\":2,\"page\":1,\"page_size\":10}")
        let orphan = try await service.groups(); XCTAssertNil(orphan.items[0].taskId)
        do { _ = try await service.groups(.init(size:101)); XCTFail("group limit bypassed") } catch {}
        for group in [groupJSON.replacingOccurrences(of:"\"count\":2",with:"\"count\":-1"),groupJSON.replacingOccurrences(of:"9007199254740995",with:"true")] {
            api.add("{\"items\":["+group+"],\"total\":1,\"finding_total\":2,\"page\":1,\"page_size\":10}")
            do { _ = try await service.groups(); XCTFail("bad group accepted") } catch {}
        }
    }
    @MainActor func testStatsLiteralClassesExactTaskIDsAndMissingNullSemantics() async throws {
        let api = FindingAPI(), service = FindingService(client:api)
        let stats = #"{"total":2,"pending":1,"critical":0,"high":2,"medium":0,"low":0,"vulnclasses":["é","é"],"tasks":[{"id":9007199254740995,"name":"literal 한국어","description":"中文","count":2}]}"#
        api.add(stats); let value = try await service.stats(); XCTAssertEqual(value.tasks.first?.id,"9007199254740995"); XCTAssertEqual(value.vulnclasses.count,2)
        XCTAssertNotEqual(Array(value.vulnclasses[0].utf8),Array(value.vulnclasses[1].utf8)); XCTAssertEqual(api.calls[0].1,"/api/exploration/findings/stats")
        for text in [stats.replacingOccurrences(of:"\"pending\":1",with:"\"pending\":-1"),stats.replacingOccurrences(of:"\"tasks\":[",with:"\"unknown\":[")] {
            api.add(text); do { _ = try await service.stats(); XCTFail("bad stats accepted") } catch {}
        }
        api.add(#"{"total":0,"pending":0,"critical":0,"high":0,"medium":0,"low":0,"vulnclasses":null,"tasks":null}"#)
        let empty = try await service.stats(); XCTAssertTrue(empty.tasks.isEmpty); XCTAssertTrue(empty.vulnclasses.isEmpty)
    }
    @MainActor func testTreeOmitsSelectedScopeAndValidatesForestWithoutUnicodeCollapse() async throws {
        let api = FindingAPI(), service = FindingService(client:api)
        api.add(treeJSON); let tree = try await service.assetTree(.init(assetScope:"a:2")); XCTAssertEqual(tree.nodes.count,2)
        XCTAssertFalse(api.calls[0].1.contains("asset_scope")); XCTAssertEqual(tree.nodes[1].kind,"future")
        for text in [treeJSON.replacingOccurrences(of:"\"parent\":\"c:1\"",with:"\"parent\":\"missing\""),treeJSON.replacingOccurrences(of:"\"parent\":\"c:1\"",with:"\"parent\":\"a:2\""),treeJSON.replacingOccurrences(of:"\"self\":1",with:"\"self\":-1"),treeJSON.replacingOccurrences(of:"\"key\":\"a:2\"",with:"\"key\":\"c:1\"")] {
            api.add(text); do { _ = try await service.assetTree(); XCTFail("invalid forest accepted") } catch {}
        }
        let equivalent = treeJSON.replacingOccurrences(of:"\"key\":\"c:1\"",with:"\"key\":\"r:é\"").replacingOccurrences(of:"\"key\":\"a:2\"",with:"\"key\":\"r:é\"").replacingOccurrences(of:"\"parent\":\"c:1\",",with:"")
        api.add(equivalent); let distinct = try await service.assetTree(); XCTAssertEqual(distinct.nodes.count,2)
        api.add(#"{"nodes":null,"finding_total":0,"truncated":true,"dropped_kinds":["endpoint"]}"#)
        let empty = try await service.assetTree(); XCTAssertTrue(empty.nodes.isEmpty); XCTAssertTrue(empty.truncated)
    }
}

extension FindingServiceTests {
    @MainActor func testAllEightPinnedBrowserQueryProjectionsMatchDecodedNativeWire() async throws {
        struct Case: Decodable {
            struct Query: Decodable { let page: Int64; let pageSize: Int; let severity: String; let status: String; let vulnclass: String; let task: String; let query: String; let sort: String; let assetScope: String? }
            let name: String; let operation: String; let query: Query; let expected: [String:String]
        }
        struct Fixture: Decodable { let baseline: String; let cases: [Case] }
        let url = try XCTUnwrap(Bundle.module.url(forResource:"Fixtures/findings-browser-filters",withExtension:"json"))
        let fixture = try JSONDecoder().decode(Fixture.self,from:Data(contentsOf:url)); XCTAssertEqual(fixture.cases.count,8)
        XCTAssertEqual(fixture.baseline,"e75ae371ad777ffd1eecdd28d2781a6519b05591")
        for item in fixture.cases {
            let api = FindingAPI(), service = FindingService(client:api), q = item.query
            let native = FindingQuery(page:q.page,size:q.pageSize,severity:FindingSeverity(rawValue:q.severity),status:FindingStatus(rawValue:q.status),vulnclass:q.vulnclass,task:q.task,search:q.query,sort:FindingSort(rawValue:q.sort)!,assetScope:q.assetScope)
            switch item.operation {
            case "flat": api.add(page([],page:q.page,size:q.pageSize)); _ = try await service.list(native)
            case "group": api.add("{\"items\":[],\"total\":0,\"finding_total\":0,\"page\":\(q.page),\"page_size\":\(q.pageSize)}"); _ = try await service.groups(native)
            case "tree": api.add(#"{"nodes":[],"finding_total":0,"truncated":false}"#); _ = try await service.assetTree(native)
            default: XCTFail("unknown fixture"); continue
            }
            let components = try XCTUnwrap(URLComponents(string:api.calls[0].1))
            let params = Dictionary(uniqueKeysWithValues:(components.queryItems ?? []).map{($0.name,$0.value ?? "")})
            XCTAssertEqual(params,item.expected,item.name)
        }
    }
    @MainActor func testCompoundPatchFailureDispatchesOnceAndNeverInfersRollbackOrRetries() async throws {
        let api = FindingAPI(), service = FindingService(client:api), target = try decode(record())
        for status in [400,404,500] {
            api.add(#"{"error":"private SQL /state/path 한국어"}"#,status:status)
            let before = api.calls.count
            do { _ = try await service.update(target,patch:.init(name:"changed",severity:.low,status:.confirmed)); XCTFail("failed patch confirmed") }
            catch { XCTAssertEqual(AppErrorMessage(error).text(language:.english).contains("private SQL"),false) }
            XCTAssertEqual(api.calls.count,before+1); XCTAssertEqual(api.calls.last?.0,"PATCH")
        }
        api.add(try record()); api.cancel = true
        let operation = Task { try await service.update(target,patch:.init(status:.pending)) }
        do { _ = try await operation.value; XCTFail("cancelled write confirmed") } catch {}
        XCTAssertEqual(api.calls.count,4)
    }
    @MainActor func testMultiNodeCycleDuplicatesRejectButBestEffortSourceLimitCanBeExceeded() async throws {
        let api = FindingAPI(), service = FindingService(client:api)
        let cycle = treeJSON.replacingOccurrences(of:"\"key\":\"c:1\",",with:"\"key\":\"c:1\",\"parent\":\"a:2\",")
        api.add(cycle); do { _ = try await service.assetTree(); XCTFail("multi-node cycle") } catch {}
        let template = #"{"key":"r:KEY.invalid","kind":"root_domain","label":"raw","self":1,"total":1,"critical":0,"high":1,"medium":0,"low":0,"last_found_at":"raw"}"#
        let nodes = (0..<3001).map{template.replacingOccurrences(of:"KEY",with:String($0))}.joined(separator:",")
        api.add("{\"nodes\":["+nodes+"],\"finding_total\":3001,\"truncated\":true,\"dropped_kinds\":[\"endpoint\",\"service\"]}")
        let retained = try await service.assetTree(); XCTAssertEqual(retained.nodes.count,3001); XCTAssertTrue(retained.truncated)
        api.add("{\"items\":["+groupJSON+","+groupJSON+"],\"total\":2,\"finding_total\":4,\"page\":1,\"page_size\":10}")
        do { _ = try await service.groups(); XCTFail("duplicate aggregate owner") } catch {}
        api.add(#"{"total":1,"pending":0,"critical":0,"high":1,"medium":0,"low":0,"vulnclasses":[],"tasks":[{"id":7,"description":"x","count":1},{"id":"7","description":"y","count":1}]}"#)
        do { _ = try await service.stats(); XCTFail("duplicate stats task") } catch {}
    }
}
