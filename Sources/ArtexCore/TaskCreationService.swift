import Foundation

public struct TaskNamedOption: Decodable, Identifiable, Sendable {
    public let id: Int64
    public let name: String
}
public struct TaskProfileOption: Decodable, Identifiable, Sendable {
    public let id: Int64
    public let name: String
    public let model: String
    private enum CodingKeys: String, CodingKey { case id, name, model }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let raw = try c.decode(String.self, forKey: .id)
        try TaskWire.validateID(raw)
        id = try BackendJSONCoding.numericID(raw)
        name = try c.decode(String.self, forKey: .name); model = try c.decode(String.self, forKey: .model)
    }
}
public struct TaskTemplateOption: Decodable, Identifiable, Sendable {
    public let id: Int64
    public let name: String
    public let description: String
    public let goal: String
    public let categoryId: Int64?
    public let interceptRules: [TaskInterceptRuleDraft]
    private enum CodingKeys: String, CodingKey { case id, name, description, goal, categoryId, interceptRules }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int64.self, forKey: .id); name = try c.decode(String.self, forKey: .name)
        description = try c.decode(String.self, forKey: .description); goal = try c.decode(String.self, forKey: .goal)
        categoryId = try c.decodeIfPresent(Int64.self, forKey: .categoryId)
        interceptRules = try c.decodeIfPresent([TaskInterceptRuleDraft].self, forKey: .interceptRules) ?? []
        guard id > 0, categoryId.map({ $0 > 0 }) ?? true else { throw BackendAPIError.invalidResponse }
    }
}

/// Read-only option projections intentionally exclude credentials and other unused profile fields.
@MainActor public final class TaskCreationService {
    private let client: any BackendJSONTransport
    public init(client: any BackendJSONTransport) { self.client = client }
    private func array<T: Decodable & Identifiable & Sendable>(_ type: T.Type, path: String, key: String? = nil) async throws -> [T] where T.ID == Int64 {
        try Task.checkCancellation()
        let response = try await client.send(method: "GET", path: path, body: nil, bearer: nil)
        try Task.checkCancellation()
        guard (200..<300).contains(response.status) else { throw BackendAPIError.status(response.status) }
        guard response.status == 200, response.body.count <= 4 * 1024 * 1024 else { throw BackendAPIError.invalidResponse }
        let decoder = JSONDecoder(); decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.userInfo[TaskCatalogArray<T>.envelopeKey] = key ?? ""
        let result: [T]
        do { result = try decoder.decode(TaskCatalogArray<T>.self, from: response.body).values }
        catch { throw BackendAPIError.invalidResponse }
        guard result.allSatisfy({ $0.id > 0 }), Set(result.map(\.id)).count == result.count else { throw BackendAPIError.invalidResponse }
        return result
    }
    public func categories() async throws -> [TaskNamedOption] { try await array(TaskNamedOption.self, path: "/api/task-categories", key: "categories") }
    public func companies() async throws -> [TaskNamedOption] { try await array(TaskNamedOption.self, path: "/api/companies") }
    public func profiles() async throws -> [TaskProfileOption] { try await array(TaskProfileOption.self, path: "/api/llm/profiles", key: "profiles") }
    public func templates() async throws -> [TaskTemplateOption] { try await array(TaskTemplateOption.self, path: "/api/task-templates", key: "templates") }
    public func sources() async throws -> [TaskRecord] { try await TaskService(client: client).list().tasks }
}

private struct TaskCatalogKey: CodingKey {
    let stringValue: String
    var intValue: Int? { nil }
    init(_ value: String) { stringValue = value }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { return nil }
}

/// Decode directly from wire bytes; Foundation JSONSerialization can strip leading BOM text.
private struct TaskCatalogArray<Value: Decodable>: Decodable {
    static var envelopeKey: CodingUserInfoKey { CodingUserInfoKey(rawValue: "artex.taskCatalogEnvelope")! }
    let values: [Value]
    init(from decoder: any Decoder) throws {
        let key = decoder.userInfo[Self.envelopeKey] as? String ?? ""
        if key.isEmpty {
            let c = try decoder.singleValueContainer()
            values = try c.decodeNil() ? [] : c.decode([Value].self)
        } else {
            let c = try decoder.container(keyedBy: TaskCatalogKey.self); let key = TaskCatalogKey(key)
            guard c.contains(key) else { throw BackendAPIError.invalidResponse }
            values = try c.decodeIfPresent([Value].self, forKey: key) ?? []
        }
    }
}
