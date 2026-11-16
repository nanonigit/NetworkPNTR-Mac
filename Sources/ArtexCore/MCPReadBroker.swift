import Foundation

public enum MCPReadScope: String, Sendable, Hashable { case agents, taskStatus }
public enum MCPReadError: Error, Equatable { case unauthorized, invalidGrant }

public struct MCPAgentSummary: Encodable, Sendable {
    public let key: String
    public let name: String
    public let enabled: Bool
}

public struct MCPTaskStatus: Encodable, Sendable {
    public let id: String
    public let status: String
    public let paused: Bool
    public let queued: Bool
    public let inputTokens: Int64
    public let outputTokens: Int64
}

/// App-owned authorization boundary; never accepts caller-selected routes or credentials.
/// The stdio/IPC layer must authenticate clients before requesting a grant.
@MainActor public final class MCPReadBroker {
    public struct Grant: Hashable, Sendable {
        fileprivate let id: UUID
        fileprivate init() { id = UUID() }
    }
    private struct Authorization {
        let scopes: Set<MCPReadScope>
        let tasks: Set<String>
        let ownership: UUID
    }
    private let client: any BackendJSONTransport
    private let ownership: @MainActor () -> UUID?
    private var grants: [Grant: Authorization] = [:]

    init(client: any BackendJSONTransport, ownership: @escaping @MainActor () -> UUID?) {
        self.client = client
        self.ownership = ownership
    }

    /// The runtime witness returns nil while stopped, and changes on each VM replacement.
    public convenience init(session: AuthenticationSession, runtimeEpoch: @escaping @MainActor () -> UUID?) throws {
        let currentRuntime = runtimeEpoch()
        guard let runtime = currentRuntime, let account = session.exportSessionGeneration else {
            throw MCPReadError.unauthorized
        }
        self.init(client: AuthenticatedBackendClient(session: session), ownership: { [weak session] in
            let currentRuntime = runtimeEpoch()
            guard currentRuntime == runtime, session?.exportSessionGeneration == account else { return nil }
            return account
        })
    }

    /// Called by the app after explicit client authorization, never by a wire request.
    public func authorize(scopes: Set<MCPReadScope>, taskIDs: Set<String> = []) throws -> Grant {
        let current = ownership()
        try Task.checkCancellation()
        guard let current else { throw MCPReadError.unauthorized }
        guard !scopes.isEmpty, grants.count < 128, taskIDs.count <= 1_000,
              scopes.contains(.taskStatus) || taskIDs.isEmpty else { throw MCPReadError.invalidGrant }
        for id in taskIDs { try TaskWire.validateID(id) }
        let grant = Grant()
        grants[grant] = Authorization(scopes: scopes, tasks: taskIDs, ownership: current)
        return grant
    }

    public func revoke(_ grant: Grant) { grants.removeValue(forKey: grant) }
    public func revokeAll() { grants.removeAll() }

    public func agents(grant: Grant, language: AppLanguage) async throws -> [MCPAgentSummary] {
        try check(grant, scope: .agents)
        let agents = try await AgentCatalogService(client: client).list()
        try check(grant, scope: .agents)
        return agents.map { .init(key: $0.key, name: $0.displayName(language: language), enabled: $0.enabled) }
    }

    public func taskStatus(grant: Grant, id: String) async throws -> MCPTaskStatus {
        try check(grant, scope: .taskStatus, taskID: id)
        let record = try await TaskService(client: client).detail(id: id)
        try check(grant, scope: .taskStatus, taskID: id)
        return .init(id: record.id, status: record.status, paused: record.paused, queued: record.queued,
                     inputTokens: record.tokens.inputTokens, outputTokens: record.tokens.outputTokens)
    }

    private func check(_ grant: Grant, scope: MCPReadScope, taskID: String? = nil) throws {
        try Task.checkCancellation()
        let current = ownership()
        try Task.checkCancellation()
        guard let current, let authorization = grants[grant],
              current == authorization.ownership, authorization.scopes.contains(scope),
              taskID.map({ authorization.tasks.contains($0) }) ?? true else {
            throw MCPReadError.unauthorized
        }
    }
}
