import Foundation

public enum CapturedHTTPMethod: String, CaseIterable, Sendable {
    case get = "GET", post = "POST", put = "PUT", delete = "DELETE", patch = "PATCH", head = "HEAD", options = "OPTIONS"
}

public struct CapturedTrafficQuery: Sendable {
    public var page: Int64 = 0
    public var size = 25
    public var host = ""
    public var method: CapturedHTTPMethod?
    public var keyword = ""
    public init() {}
    func path() throws -> String {
        guard page >= 0, (1...500).contains(size), page <= Int64.max / Int64(size),
              host.utf8.count <= 8192, keyword.utf8.count <= 8192 else { throw FindingInputError.query }
        var items = [URLQueryItem(name: "page", value: String(page)), .init(name: "size", value: String(size))]
        if !host.isEmpty { items.append(.init(name: "host", value: host)) }
        if let method { items.append(.init(name: "method", value: method.rawValue)) }
        if !keyword.isEmpty { items.append(.init(name: "q", value: keyword)) }
        return try CapturedTrafficWire.path("/api/traffic", items: items)
    }
}

enum CapturedTrafficWire {
    static func validateID(_ id: String) throws {
        guard !id.isEmpty, id.utf8.count <= 8192,
              !id.unicodeScalars.contains(where: { $0.value < 32 || $0.value == 127 }) else { throw FindingInputError.invalidID }
    }
    static func path(_ base: String, items: [URLQueryItem]) throws -> String {
        var query = URLComponents(); query.queryItems = items
        guard let value = query.percentEncodedQuery else { throw FindingInputError.query }
        let path = base + "?" + value.replacingOccurrences(of: "+", with: "%2B")
        guard path.utf8.count <= 8192 else { throw FindingInputError.query }
        return path
    }
}

/// Recorded IDs and text are opaque. Use byte identity in selections, not Swift's canonically equivalent String equality.
public struct CapturedTrafficExchange: Decodable, Sendable {
    public let id, ts, host, method, url, contentType: String
    public let status: Int
    public let responseLength: Int64
    public var identity: Data { Data(id.utf8) }
    private enum CodingKeys: String, CodingKey { case id, ts, host, method, url, contentType, status, respLen }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id); try CapturedTrafficWire.validateID(id)
        ts = try c.decode(String.self, forKey: .ts); host = try c.decode(String.self, forKey: .host)
        method = try c.decode(String.self, forKey: .method); url = try c.decode(String.self, forKey: .url)
        contentType = try c.decode(String.self, forKey: .contentType); status = try c.decode(Int.self, forKey: .status)
        responseLength = try c.decode(Int64.self, forKey: .respLen)
        guard responseLength >= 0 else { throw BackendAPIError.invalidResponse }
    }
}

public struct CapturedTrafficPage: Decodable, Sendable {
    public let enabled: Bool
    public let count, total, page: Int64?
    public let size: Int?
    public let exchanges: [CapturedTrafficExchange]
    public var isUnavailable: Bool { page == nil }
    private enum CodingKeys: String, CodingKey { case enabled, count, total, page, size, exchanges }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try c.decode(Bool.self, forKey: .enabled)
        count = c.contains(.count) ? try c.decode(Int64.self, forKey: .count) : nil
        total = c.contains(.total) ? try c.decode(Int64.self, forKey: .total) : nil
        page = c.contains(.page) ? try c.decode(Int64.self, forKey: .page) : nil
        size = c.contains(.size) ? try c.decode(Int.self, forKey: .size) : nil
        exchanges = try c.decode([CapturedTrafficExchange].self, forKey: .exchanges)
        guard Set(exchanges.map(\.identity)).count == exchanges.count else { throw BackendAPIError.invalidResponse }
        if count == nil, total == nil, page == nil, size == nil {
            guard !enabled, exchanges.isEmpty else { throw BackendAPIError.invalidResponse }
        } else {
            guard let count, let total, let page, let size, count >= 0, total >= 0, page >= 0,
                  (1...500).contains(size), page <= Int64.max / Int64(size), exchanges.count <= size else { throw BackendAPIError.invalidResponse }
        }
    }
}

/// Matches the pinned raw preview, including binary/blob display markers; never treat this text as full original bytes.
public struct CapturedTrafficDetail: Decodable, Sendable {
    public let request, response: String
    private enum CodingKeys: String, CodingKey { case request = "req", response = "resp" }
}
