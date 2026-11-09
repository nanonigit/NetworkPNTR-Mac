import Foundation

public enum AssetCatalogType: String, CaseIterable, Sendable, Decodable {
    case rootDomain = "root_domain"
    case ip, subdomain, app, service, endpoint
}

public struct AssetCatalogRow: Decodable, Identifiable, Sendable {
    public struct OpenPort: Decodable, Sendable {
        public let port: Int
        public let service: String?
    }

    public struct AuthSummary: Decodable, Sendable {
        public let type: String?
        public let username: String?
    }

    public struct ParameterSummary: Decodable, Sendable {
        public let location: String?
        public let name: String?
        public let type: String?
    }

    public let id: Int64
    public let type: AssetCatalogType
    public let companyId: Int64?
    public let taskIds: [Int64]?
    public let domain: String?
    public let rootDomain: String?
    public let ip: String?
    public let cSegment: String?
    public let port: Int?
    public let icp: String?
    public let boundDomains: [String]?
    public let openPorts: [OpenPort]?
    public let recordType: String?
    public let recordValue: [String]?
    public let bundleId: String?
    public let appName: String?
    public let category: String?
    public let appIcp: String?
    public let url: String?
    public let serviceType: String?
    public let serviceName: String?
    public let statusCode: Int?
    public let pageTitle: String?
    public let technologies: [String]?
    public let auth: [AuthSummary]?
    public let method: String?
    public let params: [ParameterSummary]?
    public let lastSeen: String
}

public struct AssetCatalogPage: Decodable, Sendable {
    public let count: Int
    public let total: Int64
    public let assets: [AssetCatalogRow]
}

public enum AssetCatalogQueryError: Error, Sendable {
    case invalidQuery
}

@MainActor public final class AssetCatalogService {
    public static let pageSizes = [25, 50, 100, 200]
    private let client: any BackendJSONTransport

    public init(client: any BackendJSONTransport) { self.client = client }

    public func list(type: AssetCatalogType, dsl: String = "", page: Int64 = 0, size: Int = 50) async throws -> AssetCatalogPage {
        guard Self.pageSizes.contains(size), page >= 0, page <= Int64.max / Int64(size) else {
            throw AssetCatalogQueryError.invalidQuery
        }
        let expression = ChatText.trim(dsl)
        var query = URLComponents()
        query.queryItems = [
            .init(name: "type", value: type.rawValue),
            .init(name: "limit", value: String(size)),
            .init(name: "offset", value: String(page * Int64(size)))
        ]
        if !expression.isEmpty {
            query.queryItems?.append(.init(name: "dsl", value: expression))
        }
        guard let encoded = query.percentEncodedQuery else { throw AssetCatalogQueryError.invalidQuery }
        let result: AssetCatalogPage = try await read("/api/assets?" + encoded.replacingOccurrences(of: "+", with: "%2B"))
        guard result.count == result.assets.count, result.count <= size, result.total >= Int64(result.count),
              result.assets.allSatisfy({ $0.id > 0 && $0.type == type }),
              Set(result.assets.map(\.id)).count == result.count else {
            throw BackendAPIError.invalidResponse
        }
        return result
    }

    public func counts() async throws -> [String: Int64] {
        let result: [String: Int64] = try await read("/api/assets/counts")
        guard result.values.allSatisfy({ $0 >= 0 }) else { throw BackendAPIError.invalidResponse }
        return result
    }

    private func read<T: Decodable>(_ path: String) async throws -> T {
        try Task.checkCancellation()
        guard path.utf8.count <= 8192 else { throw AssetCatalogQueryError.invalidQuery }
        let response = try await client.send(method: "GET", path: path, body: nil, bearer: nil)
        try Task.checkCancellation()
        guard (200..<300).contains(response.status) else { throw BackendAPIError.status(response.status) }
        guard response.status == 200, response.body.count <= 4 * 1024 * 1024 else {
            throw BackendAPIError.invalidResponse
        }
        return try BackendJSONCoding.decode(T.self, from: response.body)
    }
}
