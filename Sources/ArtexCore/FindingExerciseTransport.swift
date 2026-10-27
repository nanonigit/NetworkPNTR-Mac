import Foundation

/// A developer experiment cannot expand into task execution, arbitrary routes or unbounded reads.
@MainActor final class FindingExerciseTransport: BackendJSONTransport {
    private let client: any BackendJSONTransport
    private let maximumRequests: Int
    private let now: @MainActor () -> ContinuousClock.Instant
    private let deadline: ContinuousClock.Instant
    private(set) var requestCount = 0
    private(set) var lastMutationStatus: Int?
    private let base = "/api/exploration/findings"
    init(client: any BackendJSONTransport,maximumRequests: Int = 128,
         now: @escaping @MainActor () -> ContinuousClock.Instant = { ContinuousClock().now }) throws {
        guard (1...128).contains(maximumRequests) else { throw Self.failure() }
        self.client = client; self.maximumRequests = maximumRequests; self.now = now
        deadline = now().advanced(by:.seconds(90))
    }
    func send(method: String,path: String,body: Data?,bearer: String?) async throws -> BackendHTTPResponse {
        try Task.checkCancellation()
        guard bearer == nil, requestCount < maximumRequests, now() <= deadline,
              valid(method:method,path:path,body:body) else { throw Self.failure() }
        requestCount += 1
        if method != "GET" { lastMutationStatus = nil }
        let response = try await client.send(method:method,path:path,body:body,bearer:nil)
        try Task.checkCancellation()
        guard now() <= deadline, response.body.count <= 4 * 1024 * 1024 else { throw Self.failure() }
        if method != "GET" { lastMutationStatus = response.status }
        return response
    }
    func checkLifecycle() throws {
        try Task.checkCancellation()
        guard requestCount <= maximumRequests, now() <= deadline else { throw Self.failure() }
    }
    private func valid(method: String,path: String,body: Data?) -> Bool {
        guard let url = URLComponents(string:path), url.scheme == nil, url.host == nil, url.fragment == nil,
              url.percentEncodedPath == url.path else { return false }
        let items = url.queryItems ?? []
        guard Set(items.map(\.name)).count == items.count, items.allSatisfy({$0.value != nil}) else { return false }
        let query = Dictionary(uniqueKeysWithValues:items.map{($0.name,$0.value ?? "")})
        if method == "GET" {
            guard body == nil else { return false }
            if url.path == base+"/stats" { return query.isEmpty }
            if url.path == base || url.path == base+"/groups" || url.path == base+"/asset-tree" {
                return validQuery(query,route:url.path)
            }
            guard findingID(url.path) != nil, Set(query.keys).isSubset(of:["context_task"]) else { return false }
            return query["context_task"].map(taskID) ?? true
        }
        guard query.isEmpty else { return false }
        if method == "DELETE" { return body == nil && ["9102","9133"].contains(findingID(url.path) ?? "") }
        guard method == "PATCH", findingID(url.path) == "9101", let body, !body.isEmpty, body.count <= 64 * 1024,
              let fields = (try? JSONSerialization.jsonObject(with:body)) as? [String:Any], !fields.isEmpty,
              Set(fields.keys).isSubset(of:["name","vulnclass","severity","status"]) else { return false }
        for (key,value) in fields {
            guard let text = value as? String, text.utf8.count <= 8192 else { return false }
            if key == "severity", FindingSeverity(rawValue:text) == nil { return false }
            if key == "status", FindingStatus(rawValue:text) == nil { return false }
        }
        return true
    }
    private func validQuery(_ query: [String:String],route: String) -> Bool {
        if let task = query["task"] { return route == base && query.count == 1 && taskID(task) }
        let keys: Set<String> = ["page","limit","severity","status","vulnclass","task_id","q","sort","asset_scope"]
        guard Set(query.keys).isSubset(of:keys), query.values.allSatisfy({$0.utf8.count <= 8192}) else { return false }
        if query["page"] != nil || query["limit"] != nil {
            guard route != base+"/asset-tree", let page = query["page"].flatMap(Int.init), (1...4).contains(page),
                  query["page"] == String(page), let size = query["limit"].flatMap(Int.init), [10,20,100].contains(size), query["limit"] == String(size) else { return false }
        }
        if let severity = query["severity"], FindingSeverity(rawValue:severity) == nil { return false }
        if let status = query["status"], FindingStatus(rawValue:status) == nil { return false }
        if let sort = query["sort"], FindingSort(rawValue:sort) == nil { return false }
        if let task = query["task_id"], task != "__unassigned__", !taskID(task) { return false }
        if let scope = query["asset_scope"], !["c:8200","a:8201","a:8202","a:8203","__none__"].contains(scope) { return false }
        return true
    }
    private func findingID(_ path: String) -> String? {
        let prefix = base+"/"; guard path.hasPrefix(prefix) else { return nil }
        let value = String(path.dropFirst(prefix.count))
        guard let id = Int(value), (9101...9133).contains(id), String(id) == value else { return nil }; return value
    }
    private func taskID(_ value: String) -> Bool {
        guard let id = Int(value), (8101...8111).contains(id), String(id) == value else { return false }; return true
    }
    private static func failure() -> RuntimeError { .integrity("findings exercise transport") }
}
