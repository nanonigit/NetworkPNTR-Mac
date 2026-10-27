import Foundation

/// Finite operations only. Creation/resume can start guest agents; none are retried automatically.
@MainActor public final class TaskService {
    private let client: any BackendJSONTransport
    public init(client: any BackendJSONTransport) { self.client = client }
    private func request<T: Decodable>(_ type: T.Type, method: String, path: String, body: Data? = nil, status: Int = 200,
                                       onDispatch: @MainActor () throws -> Void = {}) async throws -> T {
        try Task.checkCancellation()
        try onDispatch()
        let response = try await client.send(method: method, path: path, body: body, bearer: nil)
        try Task.checkCancellation()
        guard (200..<300).contains(response.status) else { throw BackendAPIError.status(response.status) }
        guard response.status == status, response.body.count <= 4 * 1024 * 1024 else { throw BackendAPIError.invalidResponse }
        return try BackendJSONCoding.decode(type, from: response.body)
    }
    public func list() async throws -> TaskListSnapshot {
        try await request(TaskListSnapshot.self, method: "GET", path: "/api/tasks")
    }
    public func detail(id: String) async throws -> TaskRecord {
        let id = try TaskWire.canonicalID(id)
        let task = try await request(TaskRecord.self, method: "GET", path: "/api/tasks/" + id)
        try validate(task, owner: id); return task
    }
    public func create(_ draft: TaskCreateDraft) async throws -> TaskRecord {
        try await create(draft,onDispatch:{})
    }
    func create(_ draft: TaskCreateDraft,onDispatch: @MainActor () throws -> Void) async throws -> TaskRecord {
        let task = try await request(TaskRecord.self, method: "POST", path: "/api/tasks", body: draft.encoded(), status: 201,onDispatch:onDispatch)
        try task.validate(); return task
    }
    public func update(id: String, patch: TaskMetadataPatch) async throws -> TaskRecord {
        try await update(id:id,patch:patch,onDispatch:{})
    }
    func update(id: String,patch: TaskMetadataPatch,onDispatch: @MainActor () throws -> Void) async throws -> TaskRecord {
        let id = try TaskWire.canonicalID(id)
        let task = try await request(TaskRecord.self, method: "PATCH", path: "/api/tasks/" + id, body: patch.encoded(),onDispatch:onDispatch)
        try validate(task, owner: id); return task
    }
    public func control(id: String, action: TaskControlAction) async throws -> TaskControlResult {
        try await control(id:id,action:action,onDispatch:{})
    }
    func control(id: String,action: TaskControlAction,onDispatch: @MainActor () throws -> Void) async throws -> TaskControlResult {
        let id = try TaskWire.canonicalID(id)
        struct Body: Encodable { let action: TaskControlAction }
        let result = try await request(TaskControlResult.self, method: "POST", path: "/api/tasks/" + id + "/control", body: BackendJSONCoding.encode(Body(action: action)),onDispatch:onDispatch)
        try result.validate(id: id, action: action); return result
    }
    public func controlBatch(ids: [String], action: TaskControlAction) async throws -> [TaskBatchControlItem] {
        try await controlBatch(ids:ids,action:action,onDispatch:{})
    }
    func controlBatch(ids: [String],action: TaskControlAction,onDispatch: @MainActor () throws -> Void) async throws -> [TaskBatchControlItem] {
        var seen = Set<String>()
        let ids = try ids.map(TaskWire.canonicalID).filter { seen.insert($0).inserted }
        guard !ids.isEmpty, ids.count <= 100 else { throw TaskInputError.invalidBatch }
        struct Body: Encodable { let taskIds: [String]; let action: TaskControlAction }
        struct Reply: Decodable { let items: [TaskBatchControlItem] }
        let result = try await request(Reply.self, method: "POST", path: "/api/tasks/control/batch", body: BackendJSONCoding.encode(Body(taskIds: ids, action: action)),onDispatch:onDispatch)
        guard result.items.map(\.id) == ids else { throw BackendAPIError.invalidResponse }
        for item in result.items where item.ok {
            guard TaskWire.validStatus(item.status, queued: item.queued, action: action) else { throw BackendAPIError.invalidResponse }
        }
        return result.items
    }
    public func delete(id: String, options: TaskDeletionOptions = .init()) async throws -> TaskDeletionResult {
        try await delete(id:id,options:options,onDispatch:{})
    }
    func delete(id: String,options: TaskDeletionOptions,onDispatch: @MainActor () throws -> Void) async throws -> TaskDeletionResult {
        let id = try TaskWire.canonicalID(id)
        let result = try await request(TaskDeletionResult.self, method: "DELETE", path: "/api/tasks/" + id, body: BackendJSONCoding.encode(options),onDispatch:onDispatch)
        guard result.deleted == id else { throw BackendAPIError.invalidResponse }
        return result
    }
    private func validate(_ task: TaskRecord, owner: String) throws {
        try task.validate()
        guard task.id == owner else { throw BackendAPIError.invalidResponse }
    }
}
