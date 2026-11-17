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

    func webSearchEnabled() async throws -> Bool {
        struct Settings: Decodable { let webSearchEnabled: Bool }
        return try await fetch(Settings.self, path: "/api/settings").webSearchEnabled
    }

    func saveExecution(key: String, patch: AgentExecutionPatch) async throws {
        let body = try JSONEncoder().encode(patch)
        try await submitSettings(key: key, method: "PUT", suffix: "/config", body: body)
    }

    private func submitSettings(key: String, method: String, suffix: String, body: Data) async throws {
        let path = try agentPath(key) + suffix
        try await submitAcknowledged(method: method, path: path, body: body)
    }

    private func submitAcknowledged(method: String, path: String, body: Data) async throws {
        struct Acknowledgement: Decodable { let ok: Bool }
        try Task.checkCancellation()
        let response = try await client.send(method: method, path: path, body: body, bearer: nil)
        guard response.status == 200 else { throw BackendAPIError.status(response.status) }
        let acknowledgement = try BackendJSONCoding.decode(Acknowledgement.self, from: response.body)
        guard acknowledgement.ok else { throw BackendAPIError.invalidResponse }
    }

    func visibilityResources(_ kind: AgentVisibilityKind) async throws -> [AgentVisibilityResource] {
        struct MCP: Decodable { let id: Int64; let name: String; let transport: String }
        struct Skill: Decodable { let name: String; let description: String? }
        struct Servers: Decodable { let servers: [MCP] }
        struct Skills: Decodable { let skills: [Skill] }

        let result: [AgentVisibilityResource]
        switch kind {
        case .mcp:
            let servers = try await fetch(Servers.self, path: "/api/mcp").servers
            guard servers.allSatisfy({ $0.id > 0 }) else { throw BackendAPIError.invalidResponse }
            result = servers.map { AgentVisibilityResource(id: .mcp($0.id), name: $0.name, detail: $0.transport) }
        case .skill:
            let skills = try await fetch(Skills.self, path: "/api/skills").skills
            guard skills.allSatisfy({ !$0.name.isEmpty }) else { throw BackendAPIError.invalidResponse }
            result = skills.map { AgentVisibilityResource(id: .skill($0.name), name: $0.name, detail: $0.description) }
        }
        guard Set(result.map(\.id)).count == result.count else { throw BackendAPIError.invalidResponse }
        return result
    }

    func visibility(key: String) async throws -> AgentVisibilitySnapshot {
        try await fetch(AgentVisibilitySnapshot.self, path: agentPath(key) + "/visibility")
    }

    func setVisibility(_ target: AgentVisibilityTarget, visible: Bool, agentID: String) async throws {
        struct MCP: Encodable { let agentId: String; let kind = "mcp"; let resourceId: Int64; let visible: Bool }
        struct Skill: Encodable { let agentId: String; let skillName: String; let visible: Bool }
        _ = try BackendJSONCoding.numericID(agentID)
        let path: String
        let body: Data
        switch target {
        case let .mcp(id):
            path = "/api/visibility/toggle"
            body = try BackendJSONCoding.encode(MCP(agentId: agentID, resourceId: id, visible: visible))
        case let .skill(name):
            path = "/api/visibility/skill/toggle"
            body = try BackendJSONCoding.encode(Skill(agentId: agentID, skillName: name, visible: visible))
        }
        try await submitAcknowledged(method: "POST", path: path, body: body)
    }

    func toolBindings() async throws -> [AgentToolBinding] {
        struct Catalog: Decodable { let tools: [AgentToolBinding] }
        let tools = try await fetch(Catalog.self, path: "/api/tools").tools
        guard Set(tools.map(\.key)).count == tools.count, tools.allSatisfy({ validKey($0.key) }) else {
            throw BackendAPIError.invalidResponse
        }
        return tools
    }

    func toolBindingTrafficCapture() async throws -> Bool {
        try await fetch(TrafficCaptureSettings.self, path: "/api/settings").trafficCapture
    }

    func setToolBinding(key: String, tool: String, bound: Bool) async throws {
        struct Receipt: Decodable { let agent: String; let tool: String; let bound: Bool }
        guard validKey(tool) else { throw BackendAPIError.invalidResponse }
        let path = try agentPath(key) + "/tool-bindings/" + tool
        let body = try BackendJSONCoding.encode(bound)
        try Task.checkCancellation()
        let response = try await client.send(method: "PUT", path: path, body: body, bearer: nil)
        try Task.checkCancellation()
        guard response.status == 200 else { throw BackendAPIError.status(response.status) }
        let receipt = try BackendJSONCoding.decode(Receipt.self, from: response.body)
        guard receipt.agent == key, receipt.tool == tool, receipt.bound == bound else {
            throw BackendAPIError.invalidResponse
        }
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
        guard validKey(key) else { throw BackendAPIError.invalidResponse }
        return "/api/agents/\(key)"
    }

    private func validKey(_ key: String) -> Bool {
        guard let first = key.utf8.first, (97...122).contains(first) else { return false }
        return key.utf8.dropFirst().allSatisfy { (97...122).contains($0) || (48...57).contains($0) || $0 == 95 }
    }

    private func fetch<T: Decodable>(_ type: T.Type, path: String) async throws -> T {
        try Task.checkCancellation()
        let response = try await client.send(method: "GET", path: path, body: nil, bearer: nil)
        try Task.checkCancellation()
        guard response.status == 200 else { throw BackendAPIError.status(response.status) }
        return try BackendJSONCoding.decode(type, from: response.body)
    }
}

extension AgentCatalogService {
    private struct TriggerList: Decodable { let triggers: [AgentTrigger] }
    private struct TriggerRemoval: Decodable { let deleted: Int64 }
    private struct TriggerAgentDetail: Decodable {
        struct Agent: Decodable {
            let key: String
            let builtin: Bool
            let policy: AgentTriggerPolicy

            private enum CodingKeys: String, CodingKey { case key, builtin }

            init(from decoder: any Decoder) throws {
                let values = try decoder.container(keyedBy: CodingKeys.self)
                key = try values.decode(String.self, forKey: .key)
                builtin = try values.decode(Bool.self, forKey: .builtin)
                policy = try AgentTriggerPolicy(from: decoder)
            }
        }
        let agent: Agent
    }

    package func triggerToolNames() async throws -> [String] {
        try await toolBindings().map(\.key)
    }

    public func triggers(for agent: AgentCatalogEntry) async throws -> [AgentTrigger] {
        let path = try triggerPath(agent)
        let rows = try await fetch(TriggerList.self, path: path).triggers
        guard rows.allSatisfy({ $0.id > 0 && $0.agentKey == agent.key }),
              Set(rows.map(\.id)).count == rows.count else { throw BackendAPIError.invalidResponse }
        return rows
    }

    public func createTrigger(for agent: AgentCatalogEntry, rule: AgentTriggerRule) async throws -> [AgentTrigger] {
        let path = try triggerPath(agent)
        let rule = rule.normalizingToolNames()
        let response = try await triggerRequest(method: "POST", path: path, body: triggerBody(rule))
        let created = try BackendJSONCoding.decode(AgentTrigger.self, from: response)
        guard created.id > 0, created.agentKey == agent.key, created.rule == rule else {
            throw BackendAPIError.invalidResponse
        }
        return try await confirmedTriggers(for: agent, id: created.id, rule: rule)
    }

    public func updateTrigger(for agent: AgentCatalogEntry, id: Int64, rule: AgentTriggerRule) async throws -> [AgentTrigger] {
        let rule = rule.normalizingToolNames()
        let body = try triggerBody(rule)
        try await requireTrigger(for: agent, id: id)
        try await submitAcknowledged(method: "PATCH", path: "/api/triggers/\(id)", body: body)
        return try await confirmedTriggers(for: agent, id: id, rule: rule)
    }

    public func setTriggerEnabled(for agent: AgentCatalogEntry, id: Int64, enabled: Bool) async throws -> [AgentTrigger] {
        guard id > 0 else { throw BackendAPIError.invalidResponse }
        let rows = try await triggers(for: agent)
        guard var rule = rows.first(where: { $0.id == id })?.rule else {
            throw BackendAPIError.invalidResponse
        }
        guard rule.enabled != enabled else { return rows }
        rule.enabled = enabled
        try await submitAcknowledged(method: "PATCH", path: "/api/triggers/\(id)", body: triggerBody(rule))
        return try await confirmedTriggers(for: agent, id: id, rule: rule)
    }

    public func removeTrigger(for agent: AgentCatalogEntry, id: Int64) async throws -> [AgentTrigger] {
        try await requireTrigger(for: agent, id: id)
        let response = try await triggerRequest(method: "DELETE", path: "/api/triggers/\(id)")
        guard try BackendJSONCoding.decode(TriggerRemoval.self, from: response).deleted == id else {
            throw BackendAPIError.invalidResponse
        }
        let rows = try await triggers(for: agent)
        guard !rows.contains(where: { $0.id == id }) else { throw BackendAPIError.invalidResponse }
        return rows
    }

    public func triggerPolicy(for agent: AgentCatalogEntry) async throws -> AgentTriggerPolicy {
        guard !agent.builtin else { throw BackendAPIError.invalidResponse }
        let stored = try await fetch(TriggerAgentDetail.self, path: agentPath(agent.key)).agent
        guard stored.key == agent.key, !stored.builtin, stored.policy.isValid else {
            throw BackendAPIError.invalidResponse
        }
        return stored.policy
    }

    public func saveTriggerPolicy(for agent: AgentCatalogEntry, policy: AgentTriggerPolicy) async throws -> AgentTriggerPolicy {
        guard policy.isValid else { throw BackendAPIError.invalidResponse }
        let before = try await triggerPolicy(for: agent)
        if before == policy { return before }
        let body = try BackendJSONCoding.encode(policy)
        try await submitSettings(key: agent.key, method: "PUT", suffix: "/config", body: body)
        let stored = try await triggerPolicy(for: agent)
        guard stored == policy else { throw BackendAPIError.invalidResponse }
        return stored
    }

    private func triggerPath(_ agent: AgentCatalogEntry) throws -> String {
        guard !agent.builtin else { throw BackendAPIError.invalidResponse }
        return try agentPath(agent.key) + "/triggers"
    }

    private func triggerBody(_ rule: AgentTriggerRule) throws -> Data {
        guard rule.isValid else { throw BackendAPIError.invalidResponse }
        let body = try BackendJSONCoding.encode(rule)
        guard body.count <= 4 * 1024 * 1024 else { throw BackendAPIError.status(413) }
        return body
    }

    private func triggerRequest(method: String, path: String, body: Data? = nil) async throws -> Data {
        try Task.checkCancellation()
        let response = try await client.send(method: method, path: path, body: body, bearer: nil)
        try Task.checkCancellation()
        guard response.status == 200 else { throw BackendAPIError.status(response.status) }
        return response.body
    }

    private func requireTrigger(for agent: AgentCatalogEntry, id: Int64) async throws {
        guard id > 0, try await triggers(for: agent).contains(where: { $0.id == id }) else {
            throw BackendAPIError.invalidResponse
        }
    }

    private func confirmedTriggers(for agent: AgentCatalogEntry, id: Int64, rule: AgentTriggerRule) async throws -> [AgentTrigger] {
        let rows = try await triggers(for: agent)
        guard rows.contains(where: { $0.id == id && $0.rule == rule }) else {
            throw BackendAPIError.invalidResponse
        }
        return rows
    }
}
