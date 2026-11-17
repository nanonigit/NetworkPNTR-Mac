import Foundation

public enum TaskTemplateInputError: Error, Sendable {
    case invalid, limits
    public var key: AppStringKey { self == .invalid ? .taskTemplateValidation : .taskTemplateLimits }
}

public struct TaskTemplateDraft: Encodable, Sendable {
    public var name = ""
    public var description = ""
    public var goal = ""
    public var categoryId: Int64?
    public var interceptRules: [TaskInterceptRuleDraft] = []
    public init() {}
    public init(_ value: TaskTemplateOption) {
        name = value.name; description = value.description; goal = value.goal; categoryId = value.categoryId; interceptRules = value.interceptRules
    }
    private enum CodingKeys: String, CodingKey { case name, description, goal, categoryId, interceptRules }
    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(name, forKey: .name); try c.encode(description, forKey: .description); try c.encode(goal, forKey: .goal)
        if let categoryId { try c.encode(categoryId, forKey: .categoryId) } else { try c.encodeNil(forKey: .categoryId) }
        try c.encode(interceptRules, forKey: .interceptRules)
    }
    public func encoded() throws -> Data {
        var copy = self
        copy.name = ChatText.trim(name); copy.description = ChatText.trim(description); copy.goal = ChatText.trim(goal)
        let checkedName = copy.name.unicodeScalars.split(whereSeparator: Self.goSpace).map { String(String.UnicodeScalarView($0)) }.joined(separator: " ")
        let texts = [copy.description, copy.goal].map { raw in
            var scalars = raw.unicodeScalars
            while let first = scalars.first, Self.goSpace(first) { scalars.removeFirst() }
            while let last = scalars.last, Self.goSpace(last) { scalars.removeLast() }
            return String(scalars)
        }
        guard !checkedName.isEmpty, texts.allSatisfy({ !$0.isEmpty }), categoryId.map({ $0 > 0 }) ?? true else { throw TaskTemplateInputError.invalid }
        guard checkedName.unicodeScalars.count <= 120, texts.allSatisfy({ $0.unicodeScalars.count <= 16000 }) else { throw TaskTemplateInputError.limits }
        copy.interceptRules = interceptRules.compactMap { raw in
            var rule = raw; rule.pattern = ChatText.trim(rule.pattern); return rule.pattern.isEmpty ? nil : rule
        }
        let data = try BackendJSONCoding.encode(copy)
        guard data.count <= 512 * 1024 else { throw TaskTemplateInputError.limits }
        return data
    }
    /// Dirty-state identity must not use Swift's canonically equivalent String equality.
    public func sameBytes(as other: Self) -> Bool {
        func same(_ a: String, _ b: String) -> Bool { a.utf8.elementsEqual(b.utf8) }
        return same(name,other.name) && same(description,other.description) && same(goal,other.goal) && categoryId == other.categoryId && interceptRules.count == other.interceptRules.count && zip(interceptRules,other.interceptRules).allSatisfy {
            $0.enabled == $1.enabled && $0.action == $1.action && $0.kind == $1.kind && same($0.pattern,$1.pattern) && same($0.note,$1.note)
        }
    }
    private static func goSpace(_ value: Unicode.Scalar) -> Bool {
        let n = value.value
        return (9...13).contains(n) || [32,0x85,0xA0,0x1680,0x2028,0x2029,0x202F,0x205F,0x3000].contains(n) || (0x2000...0x200A).contains(n)
    }
}

@MainActor public final class TaskTemplateService {
    private let client: any BackendJSONTransport
    private let catalog: TaskCreationService
    public init(client: any BackendJSONTransport) { self.client = client; catalog = TaskCreationService(client: client) }
    public func list() async throws -> [TaskTemplateOption] { try await catalog.templates() }
    public func categories() async throws -> [TaskNamedOption] { try await catalog.categories() }
    public func create(_ draft: TaskTemplateDraft) async throws -> TaskTemplateOption {
        try await record(method: "POST", path: "/api/task-templates", body: draft.encoded(), status: 201)
    }
    public func update(id: Int64, draft: TaskTemplateDraft) async throws -> TaskTemplateOption {
        guard id > 0 else { throw TaskTemplateInputError.invalid }
        let value = try await record(method: "PATCH", path: "/api/task-templates/\(id)", body: draft.encoded(), status: 200)
        guard value.id == id else { throw BackendAPIError.invalidResponse }; return value
    }
    public func delete(id: Int64) async throws -> Int64 {
        guard id > 0 else { throw TaskTemplateInputError.invalid }
        struct Deleted: Decodable { let deleted: Int64 }
        let value = try BackendJSONCoding.decode(Deleted.self, from: await request(method: "DELETE", path: "/api/task-templates/\(id)", body: nil, status: 200))
        guard value.deleted == id else { throw BackendAPIError.invalidResponse }; return value.deleted
    }
    private func record(method: String, path: String, body: Data, status: Int) async throws -> TaskTemplateOption {
        try BackendJSONCoding.decode(TaskTemplateOption.self, from: await request(method: method, path: path, body: body, status: status))
    }
    private func request(method: String, path: String, body: Data?, status: Int) async throws -> Data {
        try Task.checkCancellation()
        let response = try await client.send(method: method, path: path, body: body, bearer: nil)
        try Task.checkCancellation()
        guard (200..<300).contains(response.status) else { throw BackendAPIError.status(response.status) }
        guard response.status == status, response.body.count <= 4 * 1024 * 1024 else { throw BackendAPIError.invalidResponse }
        return response.body
    }
}
