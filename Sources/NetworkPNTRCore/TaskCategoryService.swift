import Foundation

public enum TaskCategoryInputError: Error, Sendable {
    case invalid, nameLimit, invalidBatch
    public var key: AppStringKey {
        switch self {
        case .invalid: .taskCategoryValidation
        case .nameLimit: .taskCategoryNameLimit
        case .invalidBatch: .taskCategoryBatchValidation
        }
    }
}

public struct TaskCategoryRecord: Decodable, Identifiable, Sendable {
    public let id: Int64
    public let name: String
    public let taskCount: Int64
    public let createdAt: String
    public let updatedAt: String
    private enum CodingKeys: String, CodingKey { case id, name, taskCount, createdAt, updatedAt }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy:CodingKeys.self)
        id = try c.decode(Int64.self,forKey:.id); name = try c.decode(String.self,forKey:.name)
        taskCount = try c.decode(Int64.self,forKey:.taskCount)
        createdAt = try c.decode(String.self,forKey:.createdAt); updatedAt = try c.decode(String.self,forKey:.updatedAt)
        guard id > 0, taskCount >= 0 else { throw BackendAPIError.invalidResponse }
    }
}

public struct TaskCategoryBatchItem: Decodable, Sendable {
    public let id: String
    public let ok: Bool
    // Raw backend error text is not retained in native state or diagnostics.
}
public struct TaskCategoryBatchResult: Decodable, Sendable {
    public let items: [TaskCategoryBatchItem]
    public let category: TaskCategoryRecord?
    private enum CodingKeys: String, CodingKey { case items, category }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy:CodingKeys.self)
        items = try c.decode([TaskCategoryBatchItem].self,forKey:.items)
        guard c.contains(.category) else { throw BackendAPIError.invalidResponse }
        category = try c.decodeIfPresent(TaskCategoryRecord.self,forKey:.category)
    }
}

/// Finite category operations never start/resume agents or select an active task.
@MainActor public final class TaskCategoryService {
    private let client: any BackendJSONTransport
    public init(client: any BackendJSONTransport) { self.client = client }
    public func tasks() async throws -> [TaskRecord] { try await TaskService(client:client).list().tasks }
    public func list() async throws -> [TaskCategoryRecord] {
        struct Reply: Decodable {
            let categories: [TaskCategoryRecord]
            enum CodingKeys: String, CodingKey { case categories }
            init(from decoder: any Decoder) throws {
                let c = try decoder.container(keyedBy:CodingKeys.self)
                guard c.contains(.categories) else { throw BackendAPIError.invalidResponse }
                categories = try c.decodeIfPresent([TaskCategoryRecord].self,forKey:.categories) ?? []
            }
        }
        let result = try await request(Reply.self,method:"GET",path:"/api/task-categories")
        guard Set(result.categories.map(\.id)).count == result.categories.count else { throw BackendAPIError.invalidResponse }
        return result.categories
    }
    public func create(name: String) async throws -> TaskCategoryRecord {
        try await create(name:name,handoff:TaskRequestHandoff())
    }
    public func create(name: String,handoff: TaskRequestHandoff) async throws -> TaskCategoryRecord {
        try await request(TaskCategoryRecord.self,method:"POST",path:"/api/task-categories",body:Self.nameBody(name),status:201,handoff:handoff)
    }
    public func rename(id: Int64, name: String) async throws -> TaskCategoryRecord {
        try await rename(id:id,name:name,handoff:TaskRequestHandoff())
    }
    public func rename(id: Int64,name: String,handoff: TaskRequestHandoff) async throws -> TaskCategoryRecord {
        try Self.checkCategory(id)
        let row = try await request(TaskCategoryRecord.self,method:"PATCH",path:"/api/task-categories/\(id)",body:Self.nameBody(name),handoff:handoff)
        guard row.id == id else { throw BackendAPIError.invalidResponse }; return row
    }
    public func delete(id: Int64) async throws -> Int64 {
        try await delete(id:id,handoff:TaskRequestHandoff())
    }
    public func delete(id: Int64,handoff: TaskRequestHandoff) async throws -> Int64 {
        try Self.checkCategory(id)
        struct Reply: Decodable { let deleted: Int64 }
        let row = try await request(Reply.self,method:"DELETE",path:"/api/task-categories/\(id)",handoff:handoff)
        guard row.deleted == id else { throw BackendAPIError.invalidResponse }; return row.deleted
    }
    public func assign(taskID: String, categoryID: Int64?) async throws -> TaskRecord {
        try await assign(taskID:taskID,categoryID:categoryID,handoff:TaskRequestHandoff())
    }
    public func assign(taskID: String,categoryID: Int64?,handoff: TaskRequestHandoff) async throws -> TaskRecord {
        let id = try TaskWire.canonicalID(taskID); try Self.checkCategory(categoryID)
        let row = try await request(TaskRecord.self,method:"PATCH",path:"/api/tasks/\(id)/category",body:BackendJSONCoding.encode(Assignment(taskIds:nil,categoryId:categoryID)),handoff:handoff)
        try row.validate()
        guard row.id == id, row.categoryId == categoryID else { throw BackendAPIError.invalidResponse }; return row
    }
    public func assignBatch(taskIDs: [String], categoryID: Int64?) async throws -> TaskCategoryBatchResult {
        try await assignBatch(taskIDs:taskIDs,categoryID:categoryID,handoff:TaskRequestHandoff())
    }
    public func assignBatch(taskIDs: [String],categoryID: Int64?,handoff: TaskRequestHandoff) async throws -> TaskCategoryBatchResult {
        try Self.checkCategory(categoryID)
        var seen = Set<String>()
        let ids = try taskIDs.map(TaskWire.canonicalID).filter { seen.insert($0).inserted }
        guard !ids.isEmpty, ids.count <= 100 else { throw TaskCategoryInputError.invalidBatch }
        let row = try await request(TaskCategoryBatchResult.self,method:"POST",path:"/api/tasks/category/batch",body:BackendJSONCoding.encode(Assignment(taskIds:ids,categoryId:categoryID)),handoff:handoff)
        guard row.items.map(\.id) == ids else { throw BackendAPIError.invalidResponse }
        if let categoryID {
            if row.items.contains(where: { $0.ok }) {
                guard row.category?.id == categoryID else { throw BackendAPIError.invalidResponse }
            } else if let category = row.category {
                guard category.id == categoryID else { throw BackendAPIError.invalidResponse }
            }
        } else { guard row.category == nil else { throw BackendAPIError.invalidResponse } }
        return row
    }
    private static func checkCategory(_ id: Int64?) throws {
        guard id.map({ $0 > 0 }) ?? true else { throw TaskCategoryInputError.invalid }
    }
    private struct Assignment: Encodable {
        let taskIds: [String]?
        let categoryId: Int64?
        enum CodingKeys: String, CodingKey { case taskIds, categoryId }
        func encode(to encoder: any Encoder) throws {
            var c = encoder.container(keyedBy:CodingKeys.self)
            if let taskIds { try c.encode(taskIds,forKey:.taskIds) }
            if let categoryId { try c.encode(categoryId,forKey:.categoryId) } else { try c.encodeNil(forKey:.categoryId) }
        }
    }
    private static func nameBody(_ name: String) throws -> Data {
        let wire = ChatText.trim(name)
        var scalars = wire.unicodeScalars
        while let first = scalars.first, goSpace(first) { scalars.removeFirst() }
        while let last = scalars.last, goSpace(last) { scalars.removeLast() }
        guard !scalars.isEmpty else { throw TaskCategoryInputError.invalid }
        // Server validation precedes its later whitespace collapse in the database.
        guard scalars.count <= 80 else { throw TaskCategoryInputError.nameLimit }
        struct Body: Encodable { let name: String }
        return try BackendJSONCoding.encode(Body(name:wire))
    }
    private static func goSpace(_ value: Unicode.Scalar) -> Bool {
        let n = value.value
        return (9...13).contains(n) || [32,0x85,0xA0,0x1680,0x2028,0x2029,0x202F,0x205F,0x3000].contains(n) || (0x2000...0x200A).contains(n)
    }
    private func request<T: Decodable>(_ type: T.Type, method: String, path: String, body: Data? = nil, status: Int = 200,
                                       handoff: TaskRequestHandoff? = nil) async throws -> T {
        guard body.map({ $0.count <= 16 * 1024 }) ?? true else { throw TaskCategoryInputError.invalid }
        try Task.checkCancellation()
        try handoff?.begin()
        let response = try await client.send(method:method,path:path,body:body,bearer:nil)
        try Task.checkCancellation()
        guard (200..<300).contains(response.status) else { throw BackendAPIError.status(response.status) }
        guard response.status == status, response.body.count <= 4 * 1024 * 1024 else { throw BackendAPIError.invalidResponse }
        return try BackendJSONCoding.decode(type,from:response.body)
    }
}
