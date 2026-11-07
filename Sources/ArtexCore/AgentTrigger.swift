import Foundation

public struct AgentTriggerRule: Codable, Equatable, Sendable {
    public var enabled = true
    public var intervalSec = 0
    public var onFinding = false
    public var onGoalMet = false
    public var onTaskTimeout = false
    public var onToolCall = false
    public var onTaskCreate = false
    public var intervalMessage = ""
    public var findingMessage = ""
    public var goalMessage = ""
    public var taskTimeoutMessage = ""
    public var toolCallMessage = ""
    public var taskCreateMessage = ""
    public var toolNames: [String]? = []

    public init() {}

    public var isValid: Bool {
        guard (0...Int(Int32.max)).contains(intervalSec),
              intervalSec > 0 || onFinding || onGoalMet || onTaskTimeout || onToolCall || onTaskCreate else { return false }
        guard onToolCall else { return true }
        guard let toolNames, !toolNames.isEmpty else { return false }
        return toolNames.allSatisfy { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    func normalizingToolNames() -> Self {
        var result = self
        if result.toolNames == nil { result.toolNames = [] }
        return result
    }
}

public struct AgentTrigger: Decodable, Identifiable, Sendable {
    public let id: Int64
    public let agentKey: String
    public let rule: AgentTriggerRule
    public let lastFire: String?

    private enum CodingKeys: String, CodingKey { case id, agentKey, lastFire }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(Int64.self, forKey: .id)
        agentKey = try values.decode(String.self, forKey: .agentKey)
        lastFire = try values.decodeIfPresent(String.self, forKey: .lastFire)
        rule = try AgentTriggerRule(from: decoder).normalizingToolNames()
    }
}

public struct AgentTriggerPolicy: Codable, Equatable, Sendable {
    public enum RunMode: String, Codable, Sendable { case serial, parallel }
    public enum MergeMode: String, Codable, Sendable { case byTask = "by_task", all, none }

    public var triggerRunMode: RunMode
    public var triggerMergeMode: MergeMode
    public var triggerMaxParallel: Int

    public init(runMode: RunMode, mergeMode: MergeMode, maxParallel: Int) {
        triggerRunMode = runMode
        triggerMergeMode = mergeMode
        triggerMaxParallel = maxParallel
    }

    public var isValid: Bool { (0...Int(Int32.max)).contains(triggerMaxParallel) }
}
