import Foundation

public struct DashboardTokenCounts: Codable, Equatable, Sendable {
    public var inputTokens: Double = 0
    public var outputTokens: Double = 0
    public var cacheReadTokens: Double = 0
    public var cacheWriteTokens: Double = 0
    public func validate() throws {
        guard [inputTokens, outputTokens, cacheReadTokens, cacheWriteTokens].allSatisfy({
            $0.isFinite && $0 >= 0 && $0.rounded(.towardZero) == $0 && $0 < 9_223_372_036_854_775_808
        }) else { throw BackendAPIError.invalidResponse }
    }
}
public struct DashboardTask: Codable, Identifiable, Sendable {
    public let id: String
    public let description: String
    public let status: String
    public let createdAt: String
    public let createdUnix: Int64?
    public let lastActivityUnix: Int64?
    public let llmProfileId: Int64?
    public let tokens: DashboardTokenCounts?
    public let goalsTotal: Int?
    public let goalsMet: Int?
    public let inFlight: Int?
    public let engineMode: String?
    public var activityUnix: Int64 { lastActivityUnix ?? createdUnix ?? 0 }
}
public struct DashboardFinding: Codable, Identifiable, Sendable {
    public let id: String
    public let vulnclass: String
    public let severity: String
    public let summary: String
    public let ts: String
    public let taskDescription: String?
}
public struct DashboardActivity: Codable, Identifiable, Sendable {
    public let seq: Int64
    public let worker: String
    public let kind: String
    public let summary: String
    public let ts: String
    public let tool: String?
    public var id: Int64 { seq }
    public var kindLabel: String { kind == "tool_use" ? (tool ?? "tool_use") : kind }
}
public struct DashboardPending: Codable, Identifiable, Sendable {
    public let id: Int64
    public let agentName: String
    public let toolName: String
}
public struct DashboardStats: Codable, Sendable { public let llmConfigured: Bool }
public struct DashboardSettings: Codable, Sendable { public let trafficCapture: Bool }
public struct DashboardConversation: Codable, Sendable {
    public let llmProfileId: Int64?
    public let createdAt: String
    public let inputTokens: Double
    public let outputTokens: Double
    public let cacheReadTokens: Double
    public let cacheWriteTokens: Double
    public var tokens: DashboardTokenCounts {
        .init(inputTokens: inputTokens, outputTokens: outputTokens,
              cacheReadTokens: cacheReadTokens, cacheWriteTokens: cacheWriteTokens)
    }
}
public struct DashboardProfileUsage: Codable, Sendable {
    public let profileName: String
    public let tasks: Int64
    public let inputTokens: Double
    public let outputTokens: Double
    public let cacheReadTokens: Double
    public let cacheWriteTokens: Double
    public var tokens: DashboardTokenCounts {
        .init(inputTokens: inputTokens, outputTokens: outputTokens,
              cacheReadTokens: cacheReadTokens, cacheWriteTokens: cacheWriteTokens)
    }
}
public struct DashboardDayUsage: Codable, Sendable {
    public let profileName: String
    public let date: String
    public let inputTokens: Double
    public let outputTokens: Double
    public let cacheReadTokens: Double
    public var tokens: DashboardTokenCounts {
        .init(inputTokens: inputTokens, outputTokens: outputTokens, cacheReadTokens: cacheReadTokens)
    }
}
public struct DashboardUsage: Codable, Sendable {
    public let byProfile: [DashboardProfileUsage]
    public let daily: [DashboardDayUsage]
    enum CodingKeys: String, CodingKey { case byProfile, daily }
    init(byProfile: [DashboardProfileUsage], daily: [DashboardDayUsage]) {
        self.byProfile = byProfile; self.daily = daily
    }
    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        // Null database slices are empty. Missing keys remain contract failures.
        guard values.contains(.byProfile), values.contains(.daily) else { throw BackendAPIError.invalidResponse }
        byProfile = try values.decodeIfPresent([DashboardProfileUsage].self, forKey: .byProfile) ?? []
        daily = try values.decodeIfPresent([DashboardDayUsage].self, forKey: .daily) ?? []
    }
}
public struct DashboardTraffic: Codable, Identifiable, Sendable {
    public let id: String
    public let ts: String
    public let host: String
    public let method: String
    public let url: String
    public let status: Int
}
public struct DashboardFastData: Codable, Sendable {
    public let findings: [DashboardFinding]
    public let stats: DashboardStats
    public let settings: DashboardSettings
    public let pending: [DashboardPending]
    public let activity: [DashboardActivity]
    public let conversations: [DashboardConversation]
}
public struct DashboardSlowData: Codable, Sendable {
    public let profiles: [LLMProfile]
    public let usage: DashboardUsage
    public let assetCounts: [String: Int64]
    public let traffic: [DashboardTraffic]
}
public struct DashboardSnapshot: Codable, Sendable {
    public init(tasks: [DashboardTask], fast: DashboardFastData, slow: DashboardSlowData) {
        self.tasks = tasks; self.fast = fast; self.slow = slow
    }
    public let tasks: [DashboardTask]
    public let fast: DashboardFastData
    public let slow: DashboardSlowData
    public func validate() throws {
        for task in tasks { try task.tokens?.validate() }
        for conversation in fast.conversations { try conversation.tokens.validate() }
        var ledgerTaskCount: Int64 = 0
        for row in slow.usage.byProfile {
            try row.tokens.validate()
            let (next, overflow) = ledgerTaskCount.addingReportingOverflow(row.tasks)
            guard row.tasks >= 0, !overflow else { throw BackendAPIError.invalidResponse }
            ledgerTaskCount = next
        }
        for row in slow.usage.daily { try row.tokens.validate() }
        var sum: Int64 = 0
        for count in slow.assetCounts.values {
            let (next, overflow) = sum.addingReportingOverflow(count)
            guard count >= 0, !overflow else { throw BackendAPIError.invalidResponse }
            sum = next
        }
        for row in slow.traffic {
            guard (0...999).contains(row.status) else { throw BackendAPIError.invalidResponse }
        }
        for profile in slow.profiles { _ = try LLMWire.numericID(profile.id) }
    }
}

public extension DashboardFastData {
    static var empty: Self { .init(findings: [], stats: .init(llmConfigured: false), settings: .init(trafficCapture: false), pending: [], activity: [], conversations: []) }
}
public extension DashboardSlowData {
    static var empty: Self { .init(profiles: [], usage: .init(byProfile: [], daily: []), assetCounts: [:], traffic: []) }
}
