import Foundation

public struct TaskArchiveTokenStats: Decodable, Sendable {
    public let calls: Int64?
    public let inputTokens: Int64?
    public let outputTokens: Int64?
    public let cacheReadTokens: Int64?
    public let cacheWriteTokens: Int64?
    private enum CodingKeys: String, CodingKey { case calls, inputTokens, outputTokens, cacheReadTokens, cacheWriteTokens }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy:CodingKeys.self)
        calls = try c.decodeIfPresent(Int64.self,forKey:.calls); inputTokens = try c.decodeIfPresent(Int64.self,forKey:.inputTokens)
        outputTokens = try c.decodeIfPresent(Int64.self,forKey:.outputTokens); cacheReadTokens = try c.decodeIfPresent(Int64.self,forKey:.cacheReadTokens)
        cacheWriteTokens = try c.decodeIfPresent(Int64.self,forKey:.cacheWriteTokens)
        guard [calls,inputTokens,outputTokens,cacheReadTokens,cacheWriteTokens].compactMap({$0}).allSatisfy({$0 >= 0}) else { throw BackendAPIError.invalidResponse }
    }
}
public struct TaskArchiveAggregateStats: Decodable, Sendable {
    public let tokens: TaskArchiveTokenStats?
    public let skills: [String:Int64]
    public let tools: [String:Int64]
    public let findings: [String:Int64]
    private enum CodingKeys: String, CodingKey { case tokens, skills, tools, findings }
    init() { tokens = nil; skills = [:]; tools = [:]; findings = [:] }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy:CodingKeys.self)
        tokens = try c.decodeIfPresent(TaskArchiveTokenStats.self,forKey:.tokens)
        skills = try c.decodeIfPresent([String:Int64].self,forKey:.skills) ?? [:]
        tools = try c.decodeIfPresent([String:Int64].self,forKey:.tools) ?? [:]
        findings = try c.decodeIfPresent([String:Int64].self,forKey:.findings) ?? [:]
        guard [skills,tools,findings].allSatisfy({$0.values.allSatisfy({$0 >= 0})}) else { throw BackendAPIError.invalidResponse }
    }
}

/// Compact archive metadata, never a host package path or raw worker diagnostic.
public struct TaskArchiveRecord: Decodable, Identifiable, Sendable {
    public let id: Int64, taskId: Int64
    public let state: String, phase: String
    public let progress: Int64, formatVersion: Int64
    public let hasError: Bool, warningCount: Int
    public let sha256: String?
    public let originalSize: Int64, compressedSize: Int64
    public let taskName: String, taskDescription: String, taskGoal: String, originalStatus: String
    public let categoryId: Int64?
    public let categoryName: String?
    public let sourceTaskIds: [Int64]
    public let remainingTimeoutSeconds: Int64
    public let dataCounts: [String:Int64]
    public let aggregateStats: TaskArchiveAggregateStats
    public let archivedAt: String?
    public let requestedAt: String, createdAt: String, updatedAt: String
    private enum CodingKeys: String, CodingKey {
        case id, taskId, state, phase, progress, formatVersion, error, warnings, sha256, originalSize, compressedSize
        case taskName, taskDescription, taskGoal, originalStatus, categoryId, categoryName, sourceTaskIds, remainingTimeoutSeconds
        case dataCounts, aggregateStats, archivedAt, requestedAt, createdAt, updatedAt
    }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy:CodingKeys.self)
        id = try c.decode(Int64.self,forKey:.id); taskId = try c.decode(Int64.self,forKey:.taskId)
        state = try c.decode(String.self,forKey:.state); phase = try c.decode(String.self,forKey:.phase)
        progress = try c.decode(Int64.self,forKey:.progress); formatVersion = try c.decode(Int64.self,forKey:.formatVersion)
        hasError = !(try c.decodeIfPresent(String.self,forKey:.error) ?? "").isEmpty
        warningCount = (try c.decodeIfPresent([String].self,forKey:.warnings) ?? []).count
        sha256 = try c.decodeIfPresent(String.self,forKey:.sha256)
        originalSize = try c.decode(Int64.self,forKey:.originalSize); compressedSize = try c.decode(Int64.self,forKey:.compressedSize)
        taskName = try c.decode(String.self,forKey:.taskName); taskDescription = try c.decode(String.self,forKey:.taskDescription)
        taskGoal = try c.decode(String.self,forKey:.taskGoal); originalStatus = try c.decode(String.self,forKey:.originalStatus)
        categoryId = try c.decodeIfPresent(Int64.self,forKey:.categoryId); categoryName = try c.decodeIfPresent(String.self,forKey:.categoryName)
        sourceTaskIds = try c.decodeIfPresent([Int64].self,forKey:.sourceTaskIds) ?? []
        remainingTimeoutSeconds = try c.decode(Int64.self,forKey:.remainingTimeoutSeconds)
        dataCounts = try c.decodeIfPresent([String:Int64].self,forKey:.dataCounts) ?? [:]
        aggregateStats = try c.decodeIfPresent(TaskArchiveAggregateStats.self,forKey:.aggregateStats) ?? .init()
        archivedAt = try c.decodeIfPresent(String.self,forKey:.archivedAt)
        requestedAt = try c.decode(String.self,forKey:.requestedAt); createdAt = try c.decode(String.self,forKey:.createdAt); updatedAt = try c.decode(String.self,forKey:.updatedAt)
        guard id > 0, taskId > 0, categoryId.map({$0 > 0}) ?? true, sourceTaskIds.allSatisfy({$0 > 0}), Set(sourceTaskIds).count == sourceTaskIds.count,
              (0...100).contains(progress), formatVersion > 0, [originalSize,compressedSize,remainingTimeoutSeconds].allSatisfy({$0 >= 0}),
              dataCounts.values.allSatisfy({$0 >= 0}) else { throw BackendAPIError.invalidResponse }
        if let sha256, !sha256.isEmpty {
            guard sha256.utf8.count == 64, sha256.utf8.allSatisfy({(48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0)}) else { throw BackendAPIError.invalidResponse }
        }
    }
}
public struct TaskArchivePage: Decodable, Sendable {
    public let items: [TaskArchiveRecord]
    public let total: Int64, page: Int64, size: Int
    private enum CodingKeys: String, CodingKey { case items, total, page, size }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy:CodingKeys.self)
        guard c.contains(.items) else { throw BackendAPIError.invalidResponse }
        items = try c.decodeIfPresent([TaskArchiveRecord].self,forKey:.items) ?? []
        total = try c.decode(Int64.self,forKey:.total); page = try c.decode(Int64.self,forKey:.page); size = try c.decode(Int.self,forKey:.size)
        guard total >= 0, page > 0, (1...100).contains(size), items.count <= size, Set(items.map(\.id)).count == items.count else { throw BackendAPIError.invalidResponse }
    }
}
public struct TaskArchiveBatchItem: Decodable, Sendable {
    public let id: String
    public let archiveId: Int64?
    public let ok: Bool, queued: Bool
    private enum CodingKeys: String, CodingKey { case id, archiveId, ok, queued }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy:CodingKeys.self)
        id = try c.decode(String.self,forKey:.id); archiveId = try c.decodeIfPresent(Int64.self,forKey:.archiveId)
        ok = try c.decode(Bool.self,forKey:.ok); queued = try c.decode(Bool.self,forKey:.queued)
        try TaskWire.validateID(id)
        guard archiveId.map({$0 > 0}) ?? true, ok == queued, !ok || archiveId != nil else { throw BackendAPIError.invalidResponse }
    }
}
