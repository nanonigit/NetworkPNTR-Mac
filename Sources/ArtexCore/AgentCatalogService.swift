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

@MainActor public final class AgentCatalogService {
    private struct Envelope: Decodable { let agents: [AgentCatalogEntry] }

    private let client: any BackendJSONTransport

    public init(client: any BackendJSONTransport) { self.client = client }

    public func list() async throws -> [AgentCatalogEntry] {
        try Task.checkCancellation()
        let response = try await client.send(method: "GET", path: "/api/agents", body: nil, bearer: nil)
        try Task.checkCancellation()
        guard response.status == 200 else { throw BackendAPIError.status(response.status) }

        let agents = try BackendJSONCoding.decode(Envelope.self, from: response.body).agents
        guard agents.allSatisfy({ !$0.key.isEmpty }),
              Set(agents.map(\.key)).count == agents.count else {
            throw BackendAPIError.invalidResponse
        }
        return agents
    }
}
