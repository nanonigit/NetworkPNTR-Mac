import Foundation

public struct ToolRunFilter: Equatable, Sendable {
    public let explorationID: Int64?
    public let keyword: String

    public init(explorationID: Int64? = nil, keyword: String = "") {
        self.explorationID = explorationID
        self.keyword = ChatText.trim(keyword)
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.explorationID == rhs.explorationID && lhs.keyword.utf8.elementsEqual(rhs.keyword.utf8)
    }

    fileprivate var queryItems: [URLQueryItem] {
        var items: [URLQueryItem] = []
        if let explorationID { items.append(.init(name: "task", value: String(explorationID))) }
        if !keyword.isEmpty { items.append(.init(name: "q", value: keyword)) }
        return items
    }
}

public struct ToolRunRecord: Decodable, Sendable {
    public let id: Int64
    public let explorationId: Int64
    public let worker: String
    public let tool: String
    public let command: String
    public let output: String
    public let isError: Bool
    public let createdAt: String
}

public struct ToolRunPage: Decodable, Sendable {
    public let commands: [ToolRunRecord]
    public let total: Int64
}

public struct ToolRunTally: Decodable, Identifiable, Sendable {
    public var id: String { tool }
    public let tool: String
    public let total: Int64
    public let errors: Int64
}

public enum ToolRunQueryError: Error, Sendable {
    case invalidQuery
}

@MainActor public final class ToolRunService {
    public static let pageSizes = [25, 50, 100]
    private let client: any BackendJSONTransport

    public init(client: any BackendJSONTransport) { self.client = client }

    public func list(filter: ToolRunFilter = .init(), page: Int64 = 0, size: Int = 50) async throws -> ToolRunPage {
        guard Self.pageSizes.contains(size), page >= 0, page <= Int64.max / Int64(size) else {
            throw ToolRunQueryError.invalidQuery
        }
        let pagination = [URLQueryItem(name: "page", value: String(page)), .init(name: "size", value: String(size))]
        let result: ToolRunPage = try await read("/api/commands", filter: filter, additional: pagination)
        // The backend counts tool uses separately from the result join.
        guard result.total >= 0, result.commands.count <= size,
              result.commands.allSatisfy({ $0.id > 0 && (filter.explorationID == nil || $0.explorationId == filter.explorationID) })
        else { throw BackendAPIError.invalidResponse }
        return result
    }

    public func stats(filter: ToolRunFilter = .init()) async throws -> [ToolRunTally] {
        struct Reply: Decodable { let stats: [ToolRunTally] }
        let result: Reply = try await read("/api/commands/stats", filter: filter)
        guard result.stats.allSatisfy({ $0.total >= 0 && $0.errors >= 0 && $0.errors <= $0.total }) else {
            throw BackendAPIError.invalidResponse
        }
        return result.stats
    }

    private func read<T: Decodable>(
        _ route: String, filter: ToolRunFilter, additional: [URLQueryItem] = []
    ) async throws -> T {
        try Task.checkCancellation()
        guard filter.keyword.utf8.count <= 8192, filter.explorationID.map({ $0 >= 0 }) ?? true else {
            throw ToolRunQueryError.invalidQuery
        }
        let items = additional + filter.queryItems
        var url = URLComponents()
        url.queryItems = items
        let encoded = url.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B") ?? ""
        let path = encoded.isEmpty ? route : route + "?" + encoded
        guard path.utf8.count <= 8192 else { throw ToolRunQueryError.invalidQuery }
        let response = try await client.send(method: "GET", path: path, body: nil, bearer: nil)
        try Task.checkCancellation()
        guard (200..<300).contains(response.status) else { throw BackendAPIError.status(response.status) }
        guard response.status == 200, response.body.count <= 4 * 1024 * 1024 else { throw BackendAPIError.invalidResponse }
        return try BackendJSONCoding.decode(T.self, from: response.body)
    }
}
