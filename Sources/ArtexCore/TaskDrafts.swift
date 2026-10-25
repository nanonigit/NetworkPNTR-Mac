import Foundation

public enum TaskInputError: String, CaseIterable, LocalizedError, Sendable {
    case invalidID, invalidMetadata, invalidName, invalidCreation, invalidBatch
    public var key: AppStringKey {
        switch self {
        case .invalidID: .taskErrorID
        case .invalidMetadata: .taskErrorMetadata
        case .invalidName: .taskErrorName
        case .invalidCreation: .taskErrorCreation
        case .invalidBatch: .taskErrorBatch
        }
    }
    public var errorDescription: String? { AppStrings.text(key, language: .japanese) }
}

public struct TaskInterceptRuleDraft: Codable, Sendable {
    public enum Action: String, Codable, CaseIterable, Sendable { case allow, block }
    public enum Kind: String, Codable, CaseIterable, Sendable {
        case exactDomain = "exact_domain", exactIp = "exact_ip", exactUrl = "exact_url"
        case fuzzyDomain = "fuzzy_domain", fuzzyIp = "fuzzy_ip", fuzzyUrl = "fuzzy_url", cidr
    }
    public var enabled: Bool
    public var action: Action
    public var kind: Kind
    public var pattern: String
    public var note: String
    public init(enabled: Bool, action: Action, kind: Kind, pattern: String, note: String) {
        self.enabled = enabled; self.action = action; self.kind = kind; self.pattern = pattern; self.note = note
    }
}

public struct TaskCreateDraft: Encodable, Sendable {
    public var name = ""
    public var categoryId: Int64?
    public var description = ""
    public var goal = ""
    public var llmProfileIds: [Int64] = []
    public var sourceTaskIds: [String] = []
    public var companyIds: [Int64] = []
    public var timeoutSeconds: Int64 = 0
    public var planHeartbeatSeconds: Int64 = 600
    public var seedFirstIntent = false
    public var coverageEnabled = true
    public var interceptRules: [TaskInterceptRuleDraft] = []
    public init() {}
    private enum CodingKeys: String, CodingKey {
        case name, categoryId, description, goal, llmProfileIds, sourceTaskIds, companyIds
        case timeoutSeconds, planHeartbeatSeconds, seedFirstIntent, coverageEnabled, interceptRules
    }
    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(name, forKey: .name)
        if let categoryId { try c.encode(categoryId, forKey: .categoryId) } else { try c.encodeNil(forKey: .categoryId) }
        try c.encode(description, forKey: .description); try c.encode(goal, forKey: .goal)
        try c.encode(llmProfileIds, forKey: .llmProfileIds); try c.encode(sourceTaskIds, forKey: .sourceTaskIds)
        try c.encode(companyIds, forKey: .companyIds); try c.encode(timeoutSeconds, forKey: .timeoutSeconds)
        try c.encode(planHeartbeatSeconds, forKey: .planHeartbeatSeconds)
        try c.encode(seedFirstIntent, forKey: .seedFirstIntent); try c.encode(coverageEnabled, forKey: .coverageEnabled)
        try c.encode(interceptRules, forKey: .interceptRules)
    }
    public func encoded() throws -> Data {
        var copy = self
        copy.name = ChatText.trim(name); copy.description = ChatText.trim(description); copy.goal = ChatText.trim(goal)
        guard !copy.description.isEmpty, !copy.goal.isEmpty, timeoutSeconds >= 0, planHeartbeatSeconds >= 0,
              categoryId == nil || categoryId! > 0, llmProfileIds.allSatisfy({ $0 > 0 }),
              Set(llmProfileIds).count == llmProfileIds.count, sourceTaskIds.count <= 8,
              companyIds.allSatisfy({ $0 > 0 }) else { throw TaskInputError.invalidCreation }
        do { copy.sourceTaskIds = try sourceTaskIds.map(TaskWire.canonicalID) }
        catch { throw TaskInputError.invalidCreation }
        guard Set(copy.sourceTaskIds).count == copy.sourceTaskIds.count else { throw TaskInputError.invalidCreation }
        var seen = Set<Int64>()
        copy.companyIds = companyIds.filter { seen.insert($0).inserted }
        guard copy.companyIds.count <= 32 else { throw TaskInputError.invalidCreation }
        copy.interceptRules = interceptRules.compactMap { rule in
            var rule = rule; rule.pattern = ChatText.trim(rule.pattern)
            return rule.pattern.isEmpty ? nil : rule
        }
        return try BackendJSONCoding.encode(copy)
    }
}

public struct TaskMetadataPatch: Sendable {
    public var name: String?
    public var pinned: Bool?
    public init(name: String? = nil, pinned: Bool? = nil) { self.name = name; self.pinned = pinned }
    public func encoded() throws -> Data {
        guard name != nil || pinned != nil else { throw TaskInputError.invalidMetadata }
        let trimmed = name.map { ChatText.trim($0) }
        if let trimmed, trimmed.isEmpty || trimmed.unicodeScalars.count > 200 { throw TaskInputError.invalidName }
        struct Body: Encodable { let name: String?; let pinned: Bool? }
        return try BackendJSONCoding.encode(Body(name: trimmed, pinned: pinned))
    }
}
