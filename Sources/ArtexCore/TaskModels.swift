import Foundation

/// IDs remain decimal strings; JSON counters use Int64 to avoid floating-point loss.
public struct TaskRecord: Decodable, Sendable, Equatable, Identifiable {
    public let id: String
    public let explorationId: Int64
    public let name: String
    public internal(set) var categoryId: Int64?
    public internal(set) var categoryName: String?
    public let pinned: Bool
    public let pinnedAt: String?
    public let description: String
    public let goal: String
    public let status: String
    public let createdAt: String
    public let createdUnix: Int64
    public let completedAt: String
    public let completedUnix: Int64
    public let lastActivityUnix: Int64
    public let paused: Bool
    public let queued: Bool
    public let tokens: TaskTokenCounts
    public let goalsTotal: Int64
    public let goalsMet: Int64
    public let inFlight: Int64
    public let findings: TaskFindingCounts
    public let llmProfileId: Int64?
    public let llmProfileIds: [Int64]
    public let activeLlmProfileId: Int64?
    public let llmFailoverState: String
    public let llmFailoverReason: String?
    public let sourceTaskIds: [String]
    public let archiveBlockedByTaskId: String?
    public let companyIds: [Int64]?
    public let coverageEnabled: Bool
    public let engineMode: String?

    func validate() throws {
        try TaskWire.validateID(id)
        for source in sourceTaskIds { try TaskWire.validateID(source) }
        if let archiveBlockedByTaskId, !archiveBlockedByTaskId.isEmpty { try TaskWire.validateID(archiveBlockedByTaskId) }
        let optionalIDs = [categoryId, llmProfileId, activeLlmProfileId].compactMap { $0 }
        guard explorationId > 0, optionalIDs.allSatisfy({ $0 > 0 }),
              llmProfileIds.allSatisfy({ $0 > 0 }), (companyIds ?? []).allSatisfy({ $0 > 0 }),
              [goalsTotal, goalsMet, inFlight, tokens.inputTokens, tokens.outputTokens,
               tokens.cacheReadTokens, tokens.cacheWriteTokens, findings.critical, findings.high,
               findings.medium, findings.low].allSatisfy({ $0 >= 0 }) else { throw BackendAPIError.invalidResponse }
    }
}

public struct TaskTokenCounts: Decodable, Sendable, Equatable {
    public let inputTokens: Int64
    public let outputTokens: Int64
    public let cacheReadTokens: Int64
    public let cacheWriteTokens: Int64
}

public struct TaskFindingCounts: Decodable, Sendable, Equatable {
    public let critical: Int64
    public let high: Int64
    public let medium: Int64
    public let low: Int64
}

public struct TaskListSnapshot: Decodable, Sendable {
    public let tasks: [TaskRecord]
    public let activeID: String?
    private enum CodingKeys: String, CodingKey { case tasks, active }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard c.contains(.tasks) else { throw BackendAPIError.invalidResponse }
        tasks = try c.decodeIfPresent([TaskRecord].self, forKey: .tasks) ?? []
        let active = try c.decodeIfPresent(String.self, forKey: .active)
        activeID = active == "" ? nil : active
        if let activeID { try TaskWire.validateID(activeID) }
        for task in tasks { try task.validate() }
        guard Set(tasks.map(\.id)).count == tasks.count else { throw BackendAPIError.invalidResponse }
    }
}

public enum TaskControlAction: String, Encodable, Sendable { case pause, resume }
public struct TaskControlResult: Decodable, Sendable {
    public let id: String
    public let paused: Bool
    public let queued: Bool
    public let status: String
    func validate(id expected: String, action: TaskControlAction) throws {
        guard id == expected, paused == (action == .pause),
              TaskWire.validStatus(status, queued: queued, action: action) else { throw BackendAPIError.invalidResponse }
    }
}

public struct TaskBatchControlItem: Decodable, Sendable {
    public let id: String
    public let ok: Bool
    public let status: String?
    public let queued: Bool
    private enum CodingKeys: String, CodingKey { case id, ok, status, queued }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        ok = try c.decode(Bool.self, forKey: .ok)
        status = try c.decodeIfPresent(String.self, forKey: .status)
        queued = try c.decodeIfPresent(Bool.self, forKey: .queued) ?? false
        // Arbitrary server error descriptions are intentionally not retained.
    }
}

public struct TaskDeletionOptions: Encodable, Sendable {
    public var deleteAssets = false
    public var deleteTraffic = false
    public var deleteFiles = false
    public var deleteFindings = false
    public var deleteLlmRecords = false
    public init() {}
}

public struct TaskDeletionResult: Decodable, Sendable {
    public let deleted: String
    public let assetsDeleted: Int64
    public let assetsDetached: Int64
    public let trafficDeleted: Int64
    public let filesDeleted: Bool
    public let findingsDeleted: Int64
    public let llmRecordsDeleted: Int64
    public let hasCleanupWarning: Bool
    private enum CodingKeys: String, CodingKey {
        case deleted, assetsDeleted, assetsDetached, trafficDeleted, filesDeleted, findingsDeleted, llmRecordsDeleted, cleanupWarning
    }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        deleted = try c.decode(String.self, forKey: .deleted)
        assetsDeleted = try c.decode(Int64.self, forKey: .assetsDeleted)
        assetsDetached = try c.decode(Int64.self, forKey: .assetsDetached)
        trafficDeleted = try c.decode(Int64.self, forKey: .trafficDeleted)
        filesDeleted = try c.decode(Bool.self, forKey: .filesDeleted)
        findingsDeleted = try c.decode(Int64.self, forKey: .findingsDeleted)
        llmRecordsDeleted = try c.decode(Int64.self, forKey: .llmRecordsDeleted)
        hasCleanupWarning = !(try c.decodeIfPresent(String.self, forKey: .cleanupWarning) ?? "").isEmpty
        guard [assetsDeleted, assetsDetached, trafficDeleted, findingsDeleted, llmRecordsDeleted].allSatisfy({ $0 >= 0 }) else {
            throw BackendAPIError.invalidResponse
        }
    }
}

enum TaskWire {
    static func canonicalID(_ value: String) throws -> String {
        guard !value.isEmpty, value.utf8.allSatisfy({ (48...57).contains($0) }),
              let number = Int64(value), number > 0 else { throw TaskInputError.invalidID }
        return String(number)
    }
    static func validateID(_ value: String) throws {
        guard let canonical = try? canonicalID(value), canonical == value else { throw BackendAPIError.invalidResponse }
    }
    static func validStatus(_ status: String?, queued: Bool, action: TaskControlAction) -> Bool {
        action == .pause ? status == "paused" && !queued : status == (queued ? "queued" : "running")
    }
}
