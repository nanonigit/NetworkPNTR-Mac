import Foundation

/// Read-only candidate discovery over the authenticated backend. Recorded URLs are never opened.
@MainActor public struct CapturedTrafficService {
    private let client: any BackendJSONTransport
    public init(client: any BackendJSONTransport) { self.client = client }
    public func list(_ query: CapturedTrafficQuery = .init()) async throws -> CapturedTrafficPage {
        let value = try await read(CapturedTrafficPage.self, path: query.path())
        guard value.isUnavailable || (value.page == query.page && value.size == query.size) else { throw BackendAPIError.invalidResponse }
        return value
    }
    public func detail(id: String) async throws -> CapturedTrafficDetail {
        try CapturedTrafficWire.validateID(id)
        return try await read(CapturedTrafficDetail.self, path: CapturedTrafficWire.path("/api/traffic/exchange", items: [.init(name: "id", value: id)]))
    }
    private func read<T: Decodable>(_ type: T.Type, path: String) async throws -> T {
        try Task.checkCancellation()
        let response = try await client.send(method: "GET", path: path, body: nil, bearer: nil)
        try Task.checkCancellation()
        guard (200..<300).contains(response.status) else { throw BackendAPIError.status(response.status) }
        guard response.status == 200, response.body.count <= 4 * 1024 * 1024 else { throw BackendAPIError.invalidResponse }
        return try BackendJSONCoding.decode(type, from: response.body)
    }
}
