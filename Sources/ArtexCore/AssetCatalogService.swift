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

public struct AssetCatalogCompany: Decodable, Identifiable, Sendable {
    public struct ScopeRule: Decodable, Sendable {
        public let raw: String
    }

    public let id: Int64
    public let name: String
    public let assetCount: Int64
    public let scope: [ScopeRule]?
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
        let result: AssetCatalogPage = try await request("/api/assets?" + encoded.replacingOccurrences(of: "+", with: "%2B"))
        guard result.count == result.assets.count, result.count <= size, result.total >= Int64(result.count),
              result.assets.allSatisfy({ $0.id > 0 && $0.type == type }),
              Set(result.assets.map(\.id)).count == result.count else {
            throw BackendAPIError.invalidResponse
        }
        return result
    }

    public func counts() async throws -> [String: Int64] {
        let result: [String: Int64] = try await request("/api/assets/counts")
        guard result.values.allSatisfy({ $0 >= 0 }) else { throw BackendAPIError.invalidResponse }
        return result
    }

    public func companies() async throws -> [AssetCatalogCompany] {
        let result: [AssetCatalogCompany]? = try await request("/api/companies")
        let companies = result ?? []
        guard companies.allSatisfy({ $0.id > 0 && $0.assetCount >= 0 }),
              Set(companies.map(\.id)).count == companies.count else {
            throw BackendAPIError.invalidResponse
        }
        return companies
    }

    public func deleteAssets(ids: [Int64]) async throws -> Int64 {
        guard !ids.isEmpty, ids.allSatisfy({ $0 > 0 }), Set(ids).count == ids.count else {
            throw AssetCatalogQueryError.invalidQuery
        }
        let body = try BackendJSONCoding.encode(DeleteRequest(ids: ids))
        guard body.count <= 64 * 1024 else { throw AssetCatalogQueryError.invalidQuery }
        let receipt: DeleteReceipt = try await request("/api/assets", method: "DELETE", body: body)
        guard receipt.deleted >= 0, receipt.deleted <= Int64(ids.count) else {
            throw BackendAPIError.invalidResponse
        }
        return receipt.deleted
    }

    private struct DeleteRequest: Encodable { let ids: [Int64] }
    private struct DeleteReceipt: Decodable { let deleted: Int64 }

    private func request<T: Decodable>(
        _ path: String, method: String = "GET", body: Data? = nil
    ) async throws -> T {
        try Task.checkCancellation()
        guard path.utf8.count <= 8192 else { throw AssetCatalogQueryError.invalidQuery }
        let response = try await client.send(method: method, path: path, body: body, bearer: nil)
        try Task.checkCancellation()
        guard (200..<300).contains(response.status) else { throw BackendAPIError.status(response.status) }
        guard response.status == 200, response.body.count <= 4 * 1024 * 1024 else {
            throw BackendAPIError.invalidResponse
        }
        return try BackendJSONCoding.decode(T.self, from: response.body)
    }
}
