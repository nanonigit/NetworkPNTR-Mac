import Foundation

public enum FindingInputError: Error, Sendable {
    case invalidID, query, patch, readOnly, bodyLimit
    public var key: AppStringKey {
        switch self { case .readOnly: .findingReadOnly; case .query, .bodyLimit: .findingLimits; case .invalidID, .patch: .findingValidation }
    }
}
public enum FindingSort: String, Sendable { case severity, time }
public struct FindingQuery: Sendable {
    public var page: Int64, size: Int
    public var severity: FindingSeverity?
    public var status: FindingStatus?
    public var vulnclass: String, task: String, search: String
    public var sort: FindingSort
    public var assetScope: String?
    public init(page: Int64 = 1,size: Int = 20,severity: FindingSeverity? = nil,status: FindingStatus? = nil,
                vulnclass: String = "all",task: String = "all",search: String = "",sort: FindingSort = .severity,assetScope: String? = nil) {
        self.page = page; self.size = size; self.severity = severity; self.status = status; self.vulnclass = vulnclass
        self.task = task; self.search = search; self.sort = sort; self.assetScope = assetScope
    }
    func path(_ base: String,maximum: Int? = nil,includeScope: Bool = true) throws -> String {
        var items: [URLQueryItem] = []
        if let maximum {
            guard page > 0, (1...maximum).contains(size), page-1 <= Int64.max/Int64(size) else { throw FindingInputError.query }
            items += [.init(name:"page",value:String(page)),.init(name:"limit",value:String(size))]
        }
        guard search.utf8.count <= 8192, vulnclass.utf8.count <= 8192,
              !includeScope || (assetScope?.utf8.count ?? 0) <= 8192 else { throw FindingInputError.query }
        if let severity { items.append(.init(name:"severity",value:severity.rawValue)) }
        if let status { items.append(.init(name:"status",value:status.rawValue)) }
        if !vulnclass.isEmpty, vulnclass != "all" { items.append(.init(name:"vulnclass",value:vulnclass)) }
        if !task.isEmpty, task != "all" {
            let value = task == "__unassigned__" ? task : try FindingWire.canonicalID(task)
            items.append(.init(name:"task_id",value:value))
        }
        let query = ChatText.trim(search)
        if !query.isEmpty { items.append(.init(name:"q",value:query)) }
        items.append(.init(name:"sort",value:sort.rawValue))
        if includeScope, let assetScope, !assetScope.isEmpty { items.append(.init(name:"asset_scope",value:assetScope)) }
        var url = URLComponents(); url.queryItems = items
        guard let encoded = url.percentEncodedQuery?.replacingOccurrences(of:"+",with:"%2B") else { throw FindingInputError.query }
        return base + "?" + encoded
    }
}
public struct FindingPatch: Encodable, Sendable {
    public var name: String?
    public var vulnclass: String?
    public var severity: FindingSeverity?
    public var status: FindingStatus?
    public init(name: String? = nil,vulnclass: String? = nil,severity: FindingSeverity? = nil,status: FindingStatus? = nil) {
        self.name = name; self.vulnclass = vulnclass; self.severity = severity; self.status = status
    }
    func normalized() throws -> FindingPatch {
        guard name != nil || vulnclass != nil || severity != nil || status != nil else { throw FindingInputError.patch }
        return .init(name:name.map{ChatText.trim($0)},vulnclass:vulnclass.map{ChatText.trim($0)},severity:severity,status:status)
    }
    func matches(_ row: FindingRecord) -> Bool {
        (name.map{row.name.utf8.elementsEqual(FindingWire.serverTrim($0).utf8)} ?? true)
            && (vulnclass.map{row.vulnclass.utf8.elementsEqual(FindingWire.serverTrim($0).utf8)} ?? true)
            && (severity.map{$0.rawValue == row.severity} ?? true) && (status.map{$0.rawValue == row.status} ?? true)
    }
}

/// A failed compound PATCH may have committed earlier fields. No automatic write retry or rollback claim.
@MainActor public final class FindingService {
    private let client: any BackendJSONTransport
    private let base = "/api/exploration/findings"
    public init(client: any BackendJSONTransport) { self.client = client }
    public func list(_ query: FindingQuery = .init()) async throws -> FindingPage {
        let page = try await request(FindingPage.self,path:query.path(base,maximum:200))
        guard page.page == query.page, page.pageSize == query.size, page.items.allSatisfy(\.standalone) else { throw BackendAPIError.invalidResponse }
        return page
    }
    public func groups(_ query: FindingQuery = .init(size:10)) async throws -> FindingGroupsPage {
        let page = try await request(FindingGroupsPage.self,path:query.path(base+"/groups",maximum:100))
        guard page.page == query.page, page.pageSize == query.size else { throw BackendAPIError.invalidResponse }; return page
    }
    public func assetTree(_ query: FindingQuery = .init()) async throws -> FindingAssetTree {
        try await request(FindingAssetTree.self,path:query.path(base+"/asset-tree",includeScope:false))
    }
    public func stats() async throws -> FindingStats { try await request(FindingStats.self,path:base+"/stats") }
    public func forTask(id: String) async throws -> [FindingRecord] {
        let owner = try FindingWire.canonicalID(id)
        let rows = try await request([FindingRecord]?.self,path:base+"?task="+owner) ?? []
        guard Set(rows.map(\.identity)).count == rows.count, rows.allSatisfy({ row in
            row.inherited ? row.sourceTaskId == row.taskId && row.taskId != owner : row.taskId == owner
        }) else { throw BackendAPIError.invalidResponse }
        return rows
    }
    public func detail(id: String,contextTaskID: String? = nil) async throws -> FindingRecord {
        let id = try FindingWire.canonicalID(id), context = try contextTaskID.map(FindingWire.canonicalID)
        let row = try await request(FindingRecord.self,path:base+"/"+id+(context.map{"?context_task="+$0} ?? ""))
        try verify(row,id:id)
        if let context {
            guard row.inherited ? row.sourceTaskId != context : row.taskId == context else { throw BackendAPIError.invalidResponse }
        }
        return row
    }
    public func update(_ target: FindingRecord,patch: FindingPatch) async throws -> FindingRecord {
        try await update(target,patch:patch,onDispatch:{})
    }
    func update(_ target: FindingRecord,patch: FindingPatch,onDispatch: @MainActor () throws -> Void) async throws -> FindingRecord {
        let id = try mutationID(target), normalized = try patch.normalized()
        let body = try BackendJSONCoding.encode(normalized)
        guard body.count <= 64 * 1024 else { throw FindingInputError.bodyLimit }
        let row = try await request(FindingRecord.self,method:"PATCH",path:base+"/"+id,body:body,onDispatch:onDispatch)
        try verify(row,id:id)
        guard normalized.matches(row), !row.inherited else { throw BackendAPIError.invalidResponse }; return row
    }
    public func delete(_ target: FindingRecord) async throws -> FindingDeletion {
        try await delete(target,onDispatch:{})
    }
    func delete(_ target: FindingRecord,onDispatch: @MainActor () throws -> Void) async throws -> FindingDeletion {
        let id = try mutationID(target)
        let receipt = try await request(FindingDeletion.self,method:"DELETE",path:base+"/"+id,onDispatch:onDispatch)
        guard receipt.deleted, String(receipt.id) == id else { throw BackendAPIError.invalidResponse }; return receipt
    }
    private func mutationID(_ row: FindingRecord) throws -> String {
        guard row.canMutate, let id = row.findingId else { throw FindingInputError.readOnly }
        return try FindingWire.canonicalID(id)
    }
    private func verify(_ row: FindingRecord,id: String) throws {
        guard row.id == id, row.findingId == id else { throw BackendAPIError.invalidResponse }
    }
    private func request<T: Decodable>(_ type: T.Type,method: String = "GET",path: String,body: Data? = nil,
                                       onDispatch: @MainActor () throws -> Void = {}) async throws -> T {
        try Task.checkCancellation()
        try onDispatch()
        let response = try await client.send(method:method,path:path,body:body,bearer:nil)
        try Task.checkCancellation()
        guard (200..<300).contains(response.status) else { throw BackendAPIError.status(response.status) }
        guard response.status == 200, response.body.count <= 4 * 1024 * 1024 else { throw BackendAPIError.invalidResponse }
        return try BackendJSONCoding.decode(type,from:response.body)
    }
}
