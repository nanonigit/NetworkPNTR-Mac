import Foundation

@MainActor public final class DashboardService {
    private let client: any BackendJSONTransport
    public init(client: any BackendJSONTransport) { self.client = client }
    private func raw(_ path: String) async throws -> Data {
        try Task.checkCancellation()
        let result = try await client.send(method: "GET", path: path, body: nil, bearer: nil)
        try Task.checkCancellation()
        guard (200..<300).contains(result.status) else { throw BackendAPIError.status(result.status) }
        return result.body
    }
    private func get<T: Decodable & Sendable>(_ type: T.Type, _ path: String) async throws -> T {
        try BackendJSONCoding.decode(type, from: await raw(path))
    }
    private func list<T: Decodable & Sendable>(_ type: T.Type, _ path: String, key: String? = nil) async throws -> [T] {
        let data = try await raw(path)
        let root: Any
        do { root = try JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed) }
        catch { throw BackendAPIError.invalidResponse }
        let value: Any
        if let key {
            guard let dictionary = root as? [String: Any], let found = dictionary[key] else { throw BackendAPIError.invalidResponse }
            value = found
        } else { value = root }
        if value is NSNull { return [] }
        guard value is [Any] else { throw BackendAPIError.invalidResponse }
        return try BackendJSONCoding.decode([T].self, from: JSONSerialization.data(withJSONObject: value))
    }
    public func tasks() async throws -> [DashboardTask] {
        let tasks = try await list(DashboardTask.self, "/api/tasks", key: "tasks")
        try DashboardSnapshot(tasks: tasks, fast: .empty, slow: .empty).validate()
        return tasks
    }
    public func fast() async throws -> DashboardFastData {
        async let findings = list(DashboardFinding.self, "/api/exploration/findings")
        async let stats = get(DashboardStats.self, "/api/stats")
        async let settings = get(DashboardSettings.self, "/api/settings")
        async let pending = list(DashboardPending.self, "/api/intercept/pending", key: "pending")
        async let activity = list(DashboardActivity.self, "/api/exploration/activity?limit=30", key: "items")
        async let conversations = list(DashboardConversation.self, "/api/tokens/conversations")
        let data = try await DashboardFastData(findings: findings, stats: stats, settings: settings,
                                               pending: pending, activity: activity, conversations: conversations)
        try DashboardSnapshot(tasks: [], fast: data, slow: .empty).validate()
        return data
    }
    public func slow() async throws -> DashboardSlowData {
        async let traffic = list(DashboardTraffic.self, "/api/traffic?page=0&size=50", key: "exchanges")
        async let assets = get([String: Int64].self, "/api/assets/counts")
        async let profiles = list(LLMProfile.self, "/api/llm/profiles", key: "profiles")
        async let usage = get(DashboardUsage.self, "/api/tokens/usage?days=365")
        let data = try await DashboardSlowData(profiles: profiles, usage: usage, assetCounts: assets, traffic: traffic)
        try DashboardSnapshot(tasks: [], fast: .empty, slow: data).validate()
        return data
    }
}
