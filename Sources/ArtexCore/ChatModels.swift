import Foundation

public struct ChatConversation: Codable, Identifiable, Equatable, Sendable {
    public let id: Int64
    public let agentKey: String
    public let title: String
    public let llmProfileId: Int64?
    public let pinned: Bool?
    public let pinnedAt: String?
    public let running: Bool?
    public let createdAt: String
    public let updatedAt: String
    public var isPinned: Bool { pinned ?? (pinnedAt != nil) }
    public var isRunning: Bool { running ?? false }
}

/// Preserve unrecognized metadata as data, including integer identifiers beyond Double precision.
public indirect enum ChatJSONValue: Codable, Equatable, Sendable {
    case null, bool(Bool), integer(Int64), unsigned(UInt64), number(Double), string(String)
    case array([ChatJSONValue]), object([String: ChatJSONValue])

    public init(from decoder: any Decoder) throws {
        let value = try decoder.singleValueContainer()
        if value.decodeNil() { self = .null }
        else if let item = try? value.decode(Bool.self) { self = .bool(item) }
        else if let item = try? value.decode(Int64.self) { self = .integer(item) }
        else if let item = try? value.decode(UInt64.self) { self = .unsigned(item) }
        else if let item = try? value.decode(Double.self) { self = .number(item) }
        else if let item = try? value.decode(String.self) { self = .string(item) }
        else if let item = try? value.decode([ChatJSONValue].self) { self = .array(item) }
        else { self = .object(try value.decode([String: ChatJSONValue].self)) }
    }
    public func encode(to encoder: any Encoder) throws {
        var value = encoder.singleValueContainer()
        switch self {
        case .null: try value.encodeNil()
        case let .bool(item): try value.encode(item)
        case let .integer(item): try value.encode(item)
        case let .unsigned(item): try value.encode(item)
        case let .number(item): try value.encode(item)
        case let .string(item): try value.encode(item)
        case let .array(item): try value.encode(item)
        case let .object(item): try value.encode(item)
        }
    }
}

public struct ChatActivity: Codable, Identifiable, Equatable, Sendable {
    public let seq: Int64
    public let worker: String
    public let ts: String
    /// Open wire value: a future event keeps its summary/detail instead of failing enum decoding.
    public let kind: String
    public let summary: String
    public let detail: String?
    public let intentId: String?
    public let tool: String?
    public let toolUseId: String?
    public let isError: Bool?
    public let metadata: [String: ChatJSONValue]?
    public let sourceTaskId: String?
    public let inherited: Bool?
    public let mainSeg: Int64?
    public let inputTokens: Int64?
    public let outputTokens: Int64?
    public let cacheReadTokens: Int64?
    public let cacheWriteTokens: Int64?
    public var id: Int64 { seq }
}

public enum ChatTranscript {
    /// Matches the pinned browser merge: incoming records replace the same persisted seq.
    /// For an older history page, pass that page first and the current transcript as incoming.
    public static func merge(_ current: [ChatActivity], incoming: [ChatActivity]) -> [ChatActivity] {
        var bySequence: [Int64: ChatActivity] = [:]
        for item in current { bySequence[item.seq] = item }
        for item in incoming { bySequence[item.seq] = item }
        return bySequence.values.sorted { $0.seq < $1.seq }
    }
}
