import Observation

public struct AgentToolBinding: Decodable, Identifiable, Sendable {
    public let key: String
    public let enabled: Bool
    let agents: [String]?

    public var id: String { key }
    public var requiresTrafficCapture: Bool { key == "traffic_search" || key == "traffic_get" }
}

@MainActor @Observable public final class AgentToolBindingEditor {
    private let key: String
    private let service: AgentCatalogService
    private var captureEnabled = false

    public private(set) var tools: [AgentToolBinding] = []
    public private(set) var isBusy = false
    public private(set) var hasLoaded = false
    public private(set) var failure: AppErrorMessage?

    public init(key: String, service: AgentCatalogService) {
        self.key = key
        self.service = service
    }

    public func contains(_ tool: AgentToolBinding) -> Bool {
        tool.agents?.contains(key) ?? false
    }

    public func trafficGated(_ tool: AgentToolBinding) -> Bool {
        tool.requiresTrafficCapture && !captureEnabled
    }

    public func canSet(_ tool: AgentToolBinding) -> Bool {
        hasLoaded && !isBusy && failure == nil && !trafficGated(tool)
    }

    public func load() async {
        guard !isBusy else { return }
        isBusy = true
        hasLoaded = false
        failure = nil
        defer { isBusy = false }
        do {
            let catalog = try await service.toolBindings()
            let capture = try await service.toolBindingTrafficCapture()
            try Task.checkCancellation()
            tools = catalog
            captureEnabled = capture
            hasLoaded = true
        } catch {
            guard !Task.isCancelled else { return }
            failure = AppErrorMessage(error)
        }
    }

    public func set(_ id: String, bound: Bool) async {
        guard let tool = tools.first(where: { $0.id == id }), canSet(tool),
              contains(tool) != bound, !Task.isCancelled else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            try await service.setToolBinding(key: key, tool: id, bound: bound)
            let catalog = try await service.toolBindings()
            tools = catalog
            guard let saved = catalog.first(where: { $0.id == id }), contains(saved) == bound else {
                throw BackendAPIError.invalidResponse
            }
        } catch {
            failure = AppErrorMessage(error)
        }
    }
}
