import Foundation

public enum LLMFormat: String, Codable, CaseIterable, Identifiable, Sendable {
    case anthropic, openai, openaiResponses = "openai-responses"
    public var id: String { rawValue }
}

public typealias LLMWire = BackendJSONCoding

public struct LLMRetryRule: Codable, Equatable, Sendable {
    public var attempts: Int = 0
    public var intervalMs: Int = 0
    public init(attempts: Int = 0, intervalMs: Int = 0) { self.attempts = attempts; self.intervalMs = intervalMs }
    public func clamped() -> Self { Self(attempts: min(20, max(-1, attempts)), intervalMs: min(3_600_000, max(0, intervalMs))) }
}
public struct LLMRetryOverride: Codable, Equatable, Sendable {
    public var connect = LLMRetryRule()
    public var empty = LLMRetryRule()
    public var stream = LLMRetryRule()
    public init() {}
    public func clamped() -> Self {
        var value = self
        value.connect = connect.clamped(); value.empty = empty.clamped(); value.stream = stream.clamped()
        return value
    }
}
public struct LLMRetryPolicy: Codable, Equatable, Sendable {
    public var connect = LLMRetryRule()
    public var empty = LLMRetryRule()
    public var stream = LLMRetryRule()
    public var breaker = LLMRetryRule()
    public var intent = LLMRetryRule()
    public init() {}
    public func clamped() -> Self {
        var value = self
        value.connect = connect.clamped(); value.empty = empty.clamped(); value.stream = stream.clamped()
        value.breaker = breaker.clamped(); value.intent = intent.clamped()
        return value
    }
}

/// The backend response has a masked hint and deliberately no API-key property.
public struct LLMProfile: Codable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let format: LLMFormat
    public let model: String
    public let isDefault: Bool
    public let baseUrl: String?
    public let proxy: String?
    public let apiKeyHint: String?
    public let ratePerSecond: Double
    public let ratePerMinute: Double
    public let contextWindowK: Int?
    public let thinkingType: String?
    public let reasoningEffort: String?
    public let priority: Int?
    public let poolExclude: Bool?
    public let streaming: Bool?
    public let maxTokens: Int?
    public let maxTokensField: String?
    public let sessionHeaderKey: String?
    public let retry: LLMRetryOverride?
}

public struct LLMProfileDraft: Encodable, Equatable, Sendable, CustomStringConvertible {
    public var id: Int64?
    public var name = ""
    public var format: LLMFormat = .anthropic
    public var model = ""
    public var baseUrl = ""
    public var proxy = ""
    public var apiKey = ""
    public var ratePerSecond: Double = 0
    public var ratePerMinute: Double = 0
    public var contextWindowK = 0
    public var thinkingType = ""
    public var reasoningEffort = ""
    public var priority = 0
    public var poolExclude = false
    public var streaming = true
    public var maxTokens = 0
    public var maxTokensField = ""
    public var sessionHeaderKey = ""
    public var retry = LLMRetryOverride()
    public var description: String { "LLMProfileDraft(credentials: redacted)" }
    public init() {}
    public init(profile: LLMProfile) throws {
        id = try LLMWire.numericID(profile.id)
        name = profile.name; format = profile.format; model = profile.model
        baseUrl = profile.baseUrl ?? ""; proxy = profile.proxy ?? ""
        ratePerSecond = profile.ratePerSecond; ratePerMinute = profile.ratePerMinute
        contextWindowK = profile.contextWindowK ?? 0; thinkingType = profile.thinkingType ?? ""
        reasoningEffort = profile.reasoningEffort ?? ""; priority = profile.priority ?? 0
        poolExclude = profile.poolExclude ?? false; streaming = profile.streaming ?? true
        maxTokens = profile.maxTokens ?? 0; maxTokensField = profile.maxTokensField ?? ""
        sessionHeaderKey = profile.sessionHeaderKey ?? ""; retry = profile.retry ?? LLMRetryOverride()
        // Editing starts with an empty secure field; the backend preserves its stored key.
    }
    public func encoded() throws -> Data {
        var value = self
        value.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        value.model = model.trimmingCharacters(in: .whitespacesAndNewlines)
        value.baseUrl = baseUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        value.proxy = proxy.trimmingCharacters(in: .whitespacesAndNewlines)
        value.sessionHeaderKey = try validatedSessionHeader()
        guard !value.name.isEmpty, !value.model.isEmpty else { throw BackendAPIError.validation("名前とモデルを入力してください。") }
        guard ratePerSecond.isFinite, ratePerSecond >= 0, ratePerMinute.isFinite, ratePerMinute >= 0,
              (0...1000).contains(contextWindowK), maxTokens >= 0, id == nil || (id ?? 0) > 0 else {
            throw BackendAPIError.validation("レート制限・コンテキスト・出力上限を確認してください。")
        }
        value.maxTokensField = format == .openai ? maxTokensField : ""
        value.retry = retry.clamped()
        return try LLMWire.encode(value)
    }
    func validatedSessionHeader() throws -> String {
        let value = sessionHeaderKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let symbols = Array("!#$%&'*+-.^_`|~".utf8)
        guard value.utf8.allSatisfy({ (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || symbols.contains($0) }) else {
            throw BackendAPIError.validation("セッションヘッダー名に使えない文字があります。")
        }
        return value
    }
}

public struct LLMPoolMember: Decodable, Identifiable, Sendable {
    public var id: String { profileId }
    public let profileId: String
    public let name: String
    public let model: String
    public let format: String
    public let priority: Int
    public let active: Bool
    public let excluded: Bool
    public let state: String
    public let fails: Int
    public let trips: Int
    public let cooldownSecs: Int
    public let lastError: String?
    public let lastAt: String?
}
public struct LLMPoolStatus: Decodable, Sendable {
    public let enabled: Bool
    public let bindFallback: Bool
    public let chain: [LLMPoolMember]
}
