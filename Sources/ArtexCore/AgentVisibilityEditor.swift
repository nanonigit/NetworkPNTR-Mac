import Observation

public enum AgentVisibilityKind: Sendable {
    case mcp, skill
}

public enum AgentVisibilityTarget: Hashable, Sendable {
    case mcp(Int64)
    case skill(String)
}

public struct AgentVisibilityResource: Identifiable, Sendable {
    public let id: AgentVisibilityTarget
    public let name: String
    public let detail: String?
}

struct AgentVisibilitySnapshot: Decodable {
    let mcp: [Int64]?
    let skill: [String]?

    func contains(_ target: AgentVisibilityTarget) -> Bool {
        switch target {
        case let .mcp(id): mcp?.contains(id) ?? false
        case let .skill(name): skill?.contains { $0.utf8.elementsEqual(name.utf8) } ?? false
        }
    }
}

@MainActor @Observable public final class AgentVisibilityEditor {
    private let key: String
    private let service: AgentCatalogService
    private var snapshot: AgentVisibilitySnapshot?

    public private(set) var kind: AgentVisibilityKind?
    public private(set) var resources: [AgentVisibilityResource] = []
    public private(set) var isBusy = false
    public private(set) var requiresReload = false
    public private(set) var failure: AppErrorMessage?

    public init(key: String, service: AgentCatalogService) {
        self.key = key
        self.service = service
    }

    public var canEdit: Bool { snapshot != nil && !isBusy && !requiresReload }

    public func contains(_ target: AgentVisibilityTarget) -> Bool {
        snapshot?.contains(target) ?? false
    }

    public func load(_ kind: AgentVisibilityKind) async {
        guard !isBusy else { return }
        self.kind = kind
        isBusy = true
        requiresReload = false
        resources = []
        snapshot = nil
        failure = nil
        defer { isBusy = false }
        do {
            let catalog = try await service.visibilityResources(kind)
            let latest = try await service.visibility(key: key)
            guard !Task.isCancelled else { return }
            resources = catalog
            snapshot = latest
        } catch {
            guard !Task.isCancelled else { return }
            failure = AppErrorMessage(error)
            requiresReload = true
        }
    }

    public func set(_ target: AgentVisibilityTarget, visible: Bool, agentID: String) async {
        guard canEdit, contains(target) != visible,
              resources.contains(where: { $0.id == target }),
              (try? BackendJSONCoding.numericID(agentID)) != nil,
              !Task.isCancelled else { return }
        isBusy = true
        failure = nil
        defer { isBusy = false }
        do {
            try await service.setVisibility(target, visible: visible, agentID: agentID)
            let latest = try await service.visibility(key: key)
            snapshot = latest
            guard latest.contains(target) == visible else { throw BackendAPIError.invalidResponse }
        } catch {
            failure = AppErrorMessage(error)
            requiresReload = true
        }
    }
}
