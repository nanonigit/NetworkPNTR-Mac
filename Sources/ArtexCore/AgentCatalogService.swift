import Foundation

public struct AgentCatalogEntry: Decodable, Identifiable, Sendable {
    public let key: String
    public let name: String
    public let description: String
    public let builtin: Bool
    public let enabled: Bool
    public let mcpCount: Int
    public let skillCount: Int
    public let toolCount: Int

    public var id: String { key }

    private enum CodingKeys: String, CodingKey {
        case key, name, description, builtin, enabled, mcpCount, skillCount, toolCount
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        key = try values.decode(String.self, forKey: .key)
        name = try values.decode(String.self, forKey: .name)
        description = try values.decodeIfPresent(String.self, forKey: .description) ?? ""
        builtin = try values.decode(Bool.self, forKey: .builtin)
        enabled = try values.decode(Bool.self, forKey: .enabled)
        mcpCount = try values.decodeIfPresent(Int.self, forKey: .mcpCount) ?? 0
        skillCount = try values.decodeIfPresent(Int.self, forKey: .skillCount) ?? 0
        toolCount = try values.decodeIfPresent(Int.self, forKey: .toolCount) ?? 0
    }

    // The pinned server seeds reporter as an editable custom agent.
    private static let reporterName = "보고서 작성"
    private static let reporterDescription = "취약점 상세 보고서 작성: 취약점을 발견하면 자동으로 트리거되어, 증거와 실행 과정을 조회한 뒤 Markdown 보고서를 작성해 해당 취약점에 기록합니다."

    public func displayName(language: AppLanguage) -> String {
        seededLabel("name", fallback: name, reporterDefault: Self.reporterName, language: language)
    }

    public func displayDescription(language: AppLanguage) -> String {
        seededLabel("description", fallback: description, reporterDefault: Self.reporterDescription, language: language)
    }

    private func seededLabel(_ field: String, fallback: String, reporterDefault: String,
                             language: AppLanguage) -> String {
        if key == "reporter" {
            guard fallback.utf8.elementsEqual(reporterDefault.utf8) else { return fallback }
        } else {
            guard builtin || key == "retester" else { return fallback }
        }
        let resource = "agent.seed.\(key).\(field)"
        let value = AppStrings.lookup(resource, language: language)
        return value == resource ? fallback : value
    }
}

public struct AgentPromptPreview: Decodable, Sendable {
    public let rendered: String
    public let error: String?
}

@MainActor public final class AgentCatalogService {
    private struct Envelope: Decodable { let agents: [AgentCatalogEntry] }
    private struct PromptPayload: Encodable { let template: String; let note: String? }

    private let client: any BackendJSONTransport

    public init(client: any BackendJSONTransport) { self.client = client }

    public func list() async throws -> [AgentCatalogEntry] {
        let agents = try await fetch(Envelope.self, path: "/api/agents").agents
        guard agents.allSatisfy({ !$0.key.isEmpty }),
              Set(agents.map(\.key)).count == agents.count else {
            throw BackendAPIError.invalidResponse
        }
        return agents
    }

    public func promptDetails(key: String) async throws -> AgentPromptDetails {
        let path = try agentPath(key)
        let detail = try await fetch(AgentPromptDetails.self, path: path)
        guard detail.key == key,
              detail.versions.allSatisfy({ $0.version > 0 }),
              Set(detail.versions.map(\.version)).count == detail.versions.count else {
            throw BackendAPIError.invalidResponse
        }
        return detail
    }

    public func savePrompt(key: String, template: String) async throws -> Int {
        let path = try agentPath(key) + "/prompt"
        let body = try BackendJSONCoding.encode(PromptPayload(template: template, note: ""))
        guard body.count <= 4 * 1024 * 1024 else { throw BackendAPIError.status(413) }
        return try await submitPromptVersion(method: "PUT", path: path, body: body)
    }

    public func restorePromptDefault(key: String) async throws -> Int {
        let path = try agentPath(key) + "/prompt/reset"
        return try await submitPromptVersion(method: "POST", path: path, body: Data("{}".utf8))
    }

    private func submitPromptVersion(method: String, path: String, body: Data) async throws -> Int {
        struct Acknowledgement: Decodable { let version: Int }
        try Task.checkCancellation()
        let response = try await client.send(method: method, path: path, body: body, bearer: nil)
        guard response.status == 200 else { throw BackendAPIError.status(response.status) }
        let acknowledgement = try BackendJSONCoding.decode(Acknowledgement.self, from: response.body)
        guard acknowledgement.version > 0 else { throw BackendAPIError.invalidResponse }
        return acknowledgement.version
    }

    func saveWrapUp(key: String, section: AgentWrapUpSection, prompt: String, rounds: Int) async throws {
        struct Payload: Encodable { let prompt: String; let maxTurns: Int }
        let body = try BackendJSONCoding.encode(Payload(prompt: prompt, maxTurns: rounds))
        guard body.count <= 4 * 1024 * 1024 else { throw BackendAPIError.status(413) }
        try await submitSettings(key: key, method: "PUT", suffix: section.routeSuffix, body: body)
    }

    func restoreWrapUp(key: String, section: AgentWrapUpSection) async throws {
        try await submitSettings(key: key, method: "POST", suffix: section.routeSuffix + "/reset", body: Data("{}".utf8))
    }

    func saveExecution(key: String, patch: AgentExecutionPatch) async throws {
        let body = try JSONEncoder().encode(patch)
        try await submitSettings(key: key, method: "PUT", suffix: "/config", body: body)
    }

    private func submitSettings(key: String, method: String, suffix: String, body: Data) async throws {
        struct Acknowledgement: Decodable { let ok: Bool }
        let path = try agentPath(key) + suffix
        try Task.checkCancellation()
        let response = try await client.send(method: method, path: path, body: body, bearer: nil)
        guard response.status == 200 else { throw BackendAPIError.status(response.status) }
        let acknowledgement = try BackendJSONCoding.decode(Acknowledgement.self, from: response.body)
        guard acknowledgement.ok else { throw BackendAPIError.invalidResponse }
    }

    public func previewPrompt(key: String, template: String) async throws -> AgentPromptPreview {
        let path = try agentPath(key) + "/prompt/preview"
        let body = try BackendJSONCoding.encode(PromptPayload(template: template, note: nil))
        guard body.count <= 4 * 1024 * 1024 else { throw BackendAPIError.status(413) }
        try Task.checkCancellation()
        let response = try await client.send(method: "POST", path: path, body: body, bearer: nil)
        try Task.checkCancellation()
        guard response.status == 200 else { throw BackendAPIError.status(response.status) }
        return try BackendJSONCoding.decode(AgentPromptPreview.self, from: response.body)
    }

    private func agentPath(_ key: String) throws -> String {
        guard let first = key.utf8.first, (97...122).contains(first),
              key.utf8.dropFirst().allSatisfy({ (97...122).contains($0) || (48...57).contains($0) || $0 == 95 }) else {
            throw BackendAPIError.invalidResponse
        }
        return "/api/agents/\(key)"
    }

    private func fetch<T: Decodable>(_ type: T.Type, path: String) async throws -> T {
        try Task.checkCancellation()
        let response = try await client.send(method: "GET", path: path, body: nil, bearer: nil)
        try Task.checkCancellation()
        guard response.status == 200 else { throw BackendAPIError.status(response.status) }
        return try BackendJSONCoding.decode(type, from: response.body)
    }
}
