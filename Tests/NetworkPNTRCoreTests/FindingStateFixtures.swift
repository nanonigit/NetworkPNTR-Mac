import XCTest
@testable import NetworkPNTRCore

@MainActor final class FindingStateAPI: BackendJSONTransport {
    struct Call { let method: String; let path: String; let body: Data? }
    var calls: [Call] = []
    var replies: [BackendHTTPResponse] = []
    var hold = false
    var held: [CheckedContinuation<BackendHTTPResponse,Error>] = []
    func send(method: String,path: String,body: Data?,bearer: String?) async throws -> BackendHTTPResponse {
        calls.append(.init(method:method,path:path,body:body))
        if hold { return try await withCheckedThrowingContinuation{held.append($0)} }
        return replies.isEmpty ? FST.reply(status:503) : replies.removeFirst()
    }
}
enum FST {
    static func reply(_ body: String = "{}",status: Int = 200) -> BackendHTTPResponse { .init(status:status,body:Data(body.utf8)) }
    static func row(_ id: String = "7",name: String = "literal e\u{301} 中文 한국어",status: String = "pending",inherited: Bool = false) -> String {
        let encoded = String(decoding:try! JSONEncoder().encode(name),as:UTF8.self)
        return "{\"id\":\"\(id)\",\"finding_id\":\"\(id)\",\"name\":\(encoded),\"vulnclass\":\"CWE-79\",\"severity\":\"high\",\"status\":\"\(status)\",\"summary\":\"s\",\"evidence\":\"e\",\"report\":\"r\",\"task_id\":\"11\",\"source_task_id\":\"11\",\"inherited\":\(inherited),\"ts\":\"raw\"}"
    }
    static func record(_ id: String = "7",name: String = "literal e\u{301} 中文 한국어",inherited: Bool = false) throws -> FindingRecord {
        try BackendJSONCoding.decode(FindingRecord.self,from:Data(row(id,name:name,inherited:inherited).utf8))
    }
    static func page(_ ids: [String],page: Int64 = 1,size: Int = 20,total: Int64 = 100) -> BackendHTTPResponse {
        let rows = ids.map{row($0)}.joined(separator:",")
        return reply("{\"items\":[\(rows)],\"total\":\(total),\"page\":\(page),\"page_size\":\(size)}")
    }
    static func groups(_ ids: [String],page: Int64 = 1,size: Int = 10) -> BackendHTTPResponse {
        let rows = ids.map{ "{\"task_id\":\($0 == "__unassigned__" ? "null" : $0),\"task_name\":\"task\",\"task_description\":\"desc\",\"task_status\":\"done\",\"count\":2,\"critical\":0,\"high\":2,\"medium\":0,\"low\":0,\"last_found_at\":\"raw\"}" }.joined(separator:",")
        return reply("{\"items\":[\(rows)],\"total\":100,\"finding_total\":200,\"page\":\(page),\"page_size\":\(size)}")
    }
    static var tree: BackendHTTPResponse {
        let nodes = ["r:é","r:e\u{301}"].map { key in
            let encoded = String(decoding:try! JSONEncoder().encode(key),as:UTF8.self)
            return "{\"key\":\(encoded),\"kind\":\"root_domain\",\"label\":\"literal\",\"self\":1,\"total\":1,\"critical\":0,\"high\":1,\"medium\":0,\"low\":0,\"last_found_at\":\"raw\"}"
        }.joined(separator:",")
        return reply("{\"nodes\":[\(nodes)],\"finding_total\":2,\"truncated\":false}")
    }
    static var stats: BackendHTTPResponse { reply(#"{"total":2,"pending":2,"critical":0,"high":2,"medium":0,"low":0,"vulnclasses":null,"tasks":null}"#) }
    @MainActor static func reached(_ predicate: () -> Bool) async throws {
        for _ in 0..<10000 { if predicate() { return }; await Task.yield() }
        XCTFail("Expected controlled suspension"); throw CancellationError()
    }
}
