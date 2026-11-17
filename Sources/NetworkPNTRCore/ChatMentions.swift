import Foundation

public enum ChatMentionKind: String, CaseIterable, Sendable {
    case finding, asset, company, endpoint, ip, app, rootDomain = "root_domain", subdomain, service
    /// Wire labels are part of the pinned browser/server grammar, not UI localization.
    public var wireLabel: String {
        switch self {
        case .finding: "漏洞"
        case .asset: "资产"
        case .company: "企业"
        case .endpoint: "接口"
        case .ip: "IP"
        case .app: "应用"
        case .rootDomain: "域名"
        case .subdomain: "子域名"
        case .service: "服务"
        }
    }
}

public struct ChatMention: Decodable, Equatable, Sendable {
    public let kind: String
    public let id: Int64
    public let label: String
    public let description: String
    public var identity: String { "\(kind):\(id)" }
    public var token: String {
        let bracketSafe = label.replacingOccurrences(of: "[", with: "（").replacingOccurrences(of: "]", with: "）")
        // ECMAScript whitespace, including BOM and excluding Unicode NEL.
        let collapsed = bracketSafe.replacingOccurrences(
            of: "[\\t\\n\\u000B\\f\\r \\u00A0\\u1680\\u2000-\\u200A\\u2028\\u2029\\u202F\\u205F\\u3000\\uFEFF]+", with: " ", options: .regularExpression)
        // JS slice counts UTF-16 units. Normalize an isolated surrogate as Go's JSON decoder does.
        let text = String(decoding: collapsed.utf16.prefix(100), as: UTF16.self)
        return "@[\(ChatMentionKind(rawValue: kind)?.wireLabel ?? ChatMentionKind.asset.wireLabel)#\(id) \(text)]"
    }
}

public struct ChatMentionPage: Decodable, Equatable, Sendable {
    public let items: [ChatMention]
    public let nextCursor: String?
    private enum CodingKeys: CodingKey { case items, nextCursor }
    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        items = try values.decode([ChatMention].self, forKey: .items)
        let cursor = try values.decodeIfPresent(String.self, forKey: .nextCursor) ?? ""
        nextCursor = cursor.isEmpty ? nil : cursor
        guard items.count <= 20, items.allSatisfy({ $0.id > 0 && !$0.kind.isEmpty }),
              Set(items.map(\.identity)).count == items.count, ChatMentionService.validCursor(cursor) else {
            throw BackendAPIError.invalidResponse
        }
    }
}

@MainActor public final class ChatMentionService {
    private let client: any BackendJSONTransport
    public init(client: any BackendJSONTransport) { self.client = client }
    nonisolated static func validCursor(_ value: String) -> Bool {
        value.utf8.count <= 2048 && value.utf8.allSatisfy {
            (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 45 || $0 == 95
        }
    }
    public func search(kind: ChatMentionKind? = nil, query: String, cursor: String = "") async throws -> ChatMentionPage {
        // Go strings.TrimSpace uses Unicode White_Space; Foundation also removes
        // zero-width characters. Trim scalar-wise to preserve the server cursor scope.
        func isSpace(_ scalar: Unicode.Scalar) -> Bool {
            let value = scalar.value
            return (9...13).contains(value) || [32, 0x85, 0xA0, 0x1680, 0x2028, 0x2029, 0x202F, 0x205F, 0x3000].contains(value) || (0x2000...0x200A).contains(value)
        }
        var scalars = query.unicodeScalars
        while let first = scalars.first, isSpace(first) { scalars.removeFirst() }
        while let last = scalars.last, isSpace(last) { scalars.removeLast() }
        let query = String(scalars)
        guard query.unicodeScalars.count <= 200, Self.validCursor(cursor) else {
            throw BackendAPIError.validation(.mentionQuery)
        }
        var url = URLComponents()
        url.path = "/api/chat/mentions"
        url.queryItems = [URLQueryItem(name: "kind", value: kind?.rawValue ?? ""), URLQueryItem(name: "q", value: query), URLQueryItem(name: "cursor", value: cursor)]
        // Form query parsers interpret a literal plus as space.
        guard let encoded = url.percentEncodedQuery else { throw BackendAPIError.invalidResponse }
        let path = url.path + "?" + encoded.replacingOccurrences(of: "+", with: "%2B")
        let response = try await client.send(method: "GET", path: path, body: nil, bearer: nil)
        guard (200..<300).contains(response.status) else { throw BackendAPIError.status(response.status) }
        return try BackendJSONCoding.decode(ChatMentionPage.self, from: response.body)
    }
}
