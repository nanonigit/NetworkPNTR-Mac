import Foundation

public struct TaskNamedOption: Decodable, Identifiable, Sendable {
    public let id: Int64
    public let name: String
}
public struct TaskProfileOption: Decodable, Identifiable, Sendable {
    public let id: Int64
    public let name: String
    public let model: String
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
        let root: Any
        do { root = try JSONSerialization.jsonObject(with: response.body, options: .fragmentsAllowed) }
        catch { throw BackendAPIError.invalidResponse }
        let value: Any
        if let key {
            guard let envelope = root as? [String: Any], let found = envelope[key] else { throw BackendAPIError.invalidResponse }
            value = found
        } else { value = root }
        if value is NSNull { return [] }
        guard value is [Any] else { throw BackendAPIError.invalidResponse }
        let result = try BackendJSONCoding.decode([T].self, from: JSONSerialization.data(withJSONObject: value))
        guard result.allSatisfy({ $0.id > 0 }), Set(result.map(\.id)).count == result.count else { throw BackendAPIError.invalidResponse }
        return result
    }
    public func categories() async throws -> [TaskNamedOption] { try await array(TaskNamedOption.self, path: "/api/task-categories", key: "categories") }
    public func companies() async throws -> [TaskNamedOption] { try await array(TaskNamedOption.self, path: "/api/companies") }
    public func profiles() async throws -> [TaskProfileOption] { try await array(TaskProfileOption.self, path: "/api/llm/profiles", key: "profiles") }
    public func templates() async throws -> [TaskTemplateOption] { try await array(TaskTemplateOption.self, path: "/api/task-templates", key: "templates") }
    public func sources() async throws -> [TaskRecord] { try await TaskService(client: client).list().tasks }
}
