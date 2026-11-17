import Foundation

public enum TaskArchiveInputError: Error, Sendable {
    case invalid, queryLimits, batch, action
    public var key: AppStringKey {
        switch self { case .invalid: .taskArchiveValidation; case .queryLimits: .taskArchiveQueryLimits; case .batch: .taskArchiveBatchValidation; case .action: .taskArchiveActionUnavailable }
    }
}

/// A validated 202 receipt proves queue acceptance, never completion of the background job.
@MainActor public final class TaskArchiveService {
    private let client: any BackendJSONTransport
    public init(client: any BackendJSONTransport) { self.client = client }
    public func list(page: Int64 = 1, size: Int = 20, query: String = "", state: String? = nil) async throws -> TaskArchivePage {
        guard page > 0, (1...100).contains(size), page-1 <= Int64.max/Int64(size), query.utf8.count <= 4096, (state?.utf8.count ?? 0) <= 128 else { throw TaskArchiveInputError.queryLimits }
        var url = URLComponents(); url.queryItems = [.init(name:"page",value:String(page)),.init(name:"size",value:String(size))]
        if !query.isEmpty { url.queryItems?.append(.init(name:"q",value:query)) }
        if let state, !state.isEmpty { url.queryItems?.append(.init(name:"state",value:state)) }
        guard let encoded = url.percentEncodedQuery?.replacingOccurrences(of:"+",with:"%2B") else { throw TaskArchiveInputError.queryLimits }
        let result = try await request(TaskArchivePage.self,method:"GET",path:"/api/task-archives?"+encoded,status:200)
        guard result.page == page, result.size == size else { throw BackendAPIError.invalidResponse }; return result
    }
    public func detail(id: Int64) async throws -> TaskArchiveRecord {
        try check(id)
        let row = try await request(TaskArchiveRecord.self,method:"GET",path:"/api/task-archives/\(id)",status:200)
        guard row.id == id else { throw BackendAPIError.invalidResponse }; return row
    }
    public func queue(taskID: String) async throws -> TaskArchiveRecord {
        try await queue(taskID:taskID,handoff:TaskRequestHandoff())
    }
    public func queue(taskID: String,handoff: TaskRequestHandoff) async throws -> TaskArchiveRecord {
        let id = try TaskWire.canonicalID(taskID)
        let row = try await request(TaskArchiveRecord.self,method:"POST",path:"/api/tasks/\(id)/archive",status:202,handoff:handoff)
        guard String(row.taskId) == id, row.state == "archive_queued" else { throw BackendAPIError.invalidResponse }; return row
    }
    public func restore(id: Int64) async throws -> TaskArchiveRecord { try await restore(id:id,handoff:TaskRequestHandoff()) }
    public func delete(id: Int64) async throws -> TaskArchiveRecord { try await delete(id:id,handoff:TaskRequestHandoff()) }
    public func restore(id: Int64,handoff: TaskRequestHandoff) async throws -> TaskArchiveRecord { try await cold(id:id,method:"POST",suffix:"/restore",state:"restore_queued",handoff:handoff) }
    public func delete(id: Int64,handoff: TaskRequestHandoff) async throws -> TaskArchiveRecord { try await cold(id:id,method:"DELETE",suffix:"",state:"delete_queued",handoff:handoff) }
    private func cold(id: Int64, method: String, suffix: String, state: String,handoff: TaskRequestHandoff) async throws -> TaskArchiveRecord {
        try check(id)
        let row = try await request(TaskArchiveRecord.self,method:method,path:"/api/task-archives/\(id)"+suffix,status:202,handoff:handoff)
        guard row.id == id, row.state == state else { throw BackendAPIError.invalidResponse }; return row
    }
    public func retry(_ archive: TaskArchiveRecord) async throws -> TaskArchiveRecord {
        try await retry(archive,handoff:TaskRequestHandoff())
    }
    public func retry(_ archive: TaskArchiveRecord,handoff: TaskRequestHandoff) async throws -> TaskArchiveRecord {
        switch archive.state {
        case "archive_failed": try await queue(taskID:String(archive.taskId),handoff:handoff)
        case "restore_failed": try await restore(id:archive.id,handoff:handoff)
        case "delete_failed": try await delete(id:archive.id,handoff:handoff)
        default: throw TaskArchiveInputError.action
        }
    }
    public func queueBatch(taskIDs: [String]) async throws -> [TaskArchiveBatchItem] {
        try await queueBatch(taskIDs:taskIDs,handoff:TaskRequestHandoff())
    }
    public func queueBatch(taskIDs: [String],handoff: TaskRequestHandoff) async throws -> [TaskArchiveBatchItem] {
        var seen = Set<String>()
        let ids = try taskIDs.map(TaskWire.canonicalID).filter { seen.insert($0).inserted }
        guard !ids.isEmpty, ids.count <= 100 else { throw TaskArchiveInputError.batch }
        struct Body: Encodable { let taskIds: [String] }
        return try await batch(path:"/api/tasks/archive/batch",body:BackendJSONCoding.encode(Body(taskIds:ids)),ids:ids,cold:false,handoff:handoff)
    }
    public func restoreBatch(ids: [Int64]) async throws -> [TaskArchiveBatchItem] { try await restoreBatch(ids:ids,handoff:TaskRequestHandoff()) }
    public func deleteBatch(ids: [Int64]) async throws -> [TaskArchiveBatchItem] { try await deleteBatch(ids:ids,handoff:TaskRequestHandoff()) }
    public func restoreBatch(ids: [Int64],handoff: TaskRequestHandoff) async throws -> [TaskArchiveBatchItem] { try await coldBatch(ids:ids,action:"restore",handoff:handoff) }
    public func deleteBatch(ids: [Int64],handoff: TaskRequestHandoff) async throws -> [TaskArchiveBatchItem] { try await coldBatch(ids:ids,action:"delete",handoff:handoff) }
    private func coldBatch(ids raw: [Int64], action: String,handoff: TaskRequestHandoff) async throws -> [TaskArchiveBatchItem] {
        guard !raw.isEmpty, raw.count <= 100, raw.allSatisfy({$0 > 0}) else { throw TaskArchiveInputError.batch }
        var seen = Set<Int64>(); let ids = raw.filter { seen.insert($0).inserted }
        struct Body: Encodable { let archiveIds: [Int64] }
        return try await batch(path:"/api/task-archives/\(action)/batch",body:BackendJSONCoding.encode(Body(archiveIds:ids)),ids:ids.map(String.init),cold:true,handoff:handoff)
    }
    private func batch(path: String, body: Data, ids: [String], cold: Bool,handoff: TaskRequestHandoff) async throws -> [TaskArchiveBatchItem] {
        struct Reply: Decodable { let items: [TaskArchiveBatchItem] }
        let result = try await request(Reply.self,method:"POST",path:path,body:body,status:202,handoff:handoff)
        guard result.items.count == ids.count, Set(result.items.map(\.id)) == Set(ids) else { throw BackendAPIError.invalidResponse }
        let accepted = result.items.filter(\.ok).compactMap(\.archiveId)
        guard Set(accepted).count == accepted.count else { throw BackendAPIError.invalidResponse }
        if cold { guard result.items.allSatisfy({$0.archiveId == Int64($0.id)}) else { throw BackendAPIError.invalidResponse } }
        return result.items
    }
    private func check(_ id: Int64) throws { guard id > 0 else { throw TaskArchiveInputError.invalid } }
    private func request<T: Decodable>(_ type: T.Type, method: String, path: String, body: Data? = nil, status: Int,
                                       handoff: TaskRequestHandoff? = nil) async throws -> T {
        guard body.map({$0.count <= 16 * 1024}) ?? true else { throw TaskArchiveInputError.batch }
        try Task.checkCancellation()
        try handoff?.begin()
        let response = try await client.send(method:method,path:path,body:body,bearer:nil)
        try Task.checkCancellation()
        guard (200..<300).contains(response.status) else { throw BackendAPIError.status(response.status) }
        guard response.status == status, response.body.count <= 4 * 1024 * 1024 else { throw BackendAPIError.invalidResponse }
        return try BackendJSONCoding.decode(type,from:response.body)
    }
}
