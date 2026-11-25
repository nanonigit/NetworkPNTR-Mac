import Foundation

public enum GuestLogLevel: String, CaseIterable, Sendable {
    case info, warning = "warn", error
}

public struct GuestLogEntry: Decodable, Identifiable, Sendable {
    public enum ID: Hashable, Sendable { case live(Int64), persisted(Int64) }

    public let seq: Int64
    public let dbId: Int64?
    public let ts: String
    public let level: String
    public let tag: String
    public let text: String

    public var id: ID { seq == 0 ? .persisted(dbId ?? 0) : .live(seq) }
    public var message: String {
        let prefix = "[\(tag)]"
        guard !tag.isEmpty, text.hasPrefix(prefix) else { return text }
        return String(text.dropFirst(prefix.count).drop(while: \.isWhitespace))
    }
}

public struct GuestLogRecentPage: Sendable {
    public let items: [GuestLogEntry]
    public let cursor: Int64
}

public struct GuestLogHistoryPage: Decodable, Sendable {
    public let items: [GuestLogEntry]
    public let hasMore: Bool
}

@MainActor public final class GuestLogService {
    private let client: any BackendJSONTransport

    public init(client: any BackendJSONTransport) { self.client = client }

    public func recent(since: Int64) async throws -> GuestLogRecentPage {
        struct Reply: Decodable { let items: [GuestLogEntry]?; let cursor: Int64 }
        guard since >= 0 else { throw BackendAPIError.invalidResponse }
        let limit = 1_000
        let reply: Reply = try await read("/api/logs?since=\(since)&limit=\(limit)")
        let rows = reply.items ?? []
        // The backend prepends restored rows with newer sequence IDs than earlier startup rows.
        guard reply.cursor >= 0, rows.count <= limit,
              rows.allSatisfy({ $0.seq > since && $0.seq <= reply.cursor && ($0.dbId ?? 1) > 0 }),
              Set(rows.map(\.seq)).count == rows.count
        else { throw BackendAPIError.invalidResponse }
        return GuestLogRecentPage(items: rows, cursor: reply.cursor)
    }

    public func history(before: Int64) async throws -> GuestLogHistoryPage {
        guard before > 0 else { throw BackendAPIError.invalidResponse }
        let limit = 200
        let reply: GuestLogHistoryPage = try await read("/api/logs/history?before=\(before)&limit=\(limit)")
        guard reply.items.count <= limit, !reply.hasMore || !reply.items.isEmpty else {
            throw BackendAPIError.invalidResponse
        }
        var previous: Int64 = 0
        for row in reply.items {
            guard row.seq == 0, let id = row.dbId, id > previous, id < before else {
                throw BackendAPIError.invalidResponse
            }
            previous = id
        }
        return reply
    }

    private func read<T: Decodable>(_ path: String) async throws -> T {
        try Task.checkCancellation()
        let response = try await client.send(method: "GET", path: path, body: nil, bearer: nil)
        try Task.checkCancellation()
        guard response.status == 200 else { throw BackendAPIError.status(response.status) }
        guard response.body.count <= 4 * 1024 * 1024 else { throw BackendAPIError.invalidResponse }
        return try BackendJSONCoding.decode(T.self, from: response.body)
    }
}
