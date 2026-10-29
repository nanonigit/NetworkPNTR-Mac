import Foundation

/// Shared integrity fields only; transport APIs remain finite and typed by resource.
protocol EvidenceBodyManifest: Sendable {
    var expectedSize: Int64 { get }
    var expectedSHA256: String { get }
}

/// A structural exchange-side manifest, never inferred from a rendered body marker.
public struct TrafficBlobDownload: Sendable, Decodable, EvidenceBodyManifest {
    public let trafficID: String
    public let side: FindingEvidenceSide
    public let expectedSize: Int64
    public let expectedSHA256: String
    public var identity: Data { Data(trafficID.utf8) }
    public var suggestedFilename: String { "traffic-" + side.rawValue + "-" + expectedSHA256.prefix(12) + ".bin" }
    public init(trafficID: String, side: FindingEvidenceSide, expectedSize: Int64, expectedSHA256: String) throws {
        try CapturedTrafficWire.validateID(trafficID)
        guard expectedSize >= 0, expectedSHA256.utf8.count == 64,
              expectedSHA256.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else {
            throw EvidenceExportError.invalidManifest
        }
        self.trafficID = trafficID; self.side = side; self.expectedSize = expectedSize; self.expectedSHA256 = expectedSHA256
    }
    private enum CodingKeys: String, CodingKey { case id, side, hash, size }
    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        guard let side = FindingEvidenceSide(rawValue: try values.decode(String.self, forKey: .side)) else { throw EvidenceExportError.invalidManifest }
        try self.init(trafficID: values.decode(String.self, forKey: .id), side: side,
                      expectedSize: values.decode(Int64.self, forKey: .size), expectedSHA256: values.decode(String.self, forKey: .hash))
    }
    func request(bearer: String) throws -> Data {
        guard !bearer.isEmpty else { throw BackendAPIError.invalidResponse }
        let base = try BackendHTTPRequest.make(method: "GET", path: "/api/traffic/blob?hash=" + expectedSHA256, body: nil, bearer: bearer)
        return Data(String(decoding: base, as: UTF8.self).replacingOccurrences(of: "Accept: application/json\r\n", with: "Accept: application/octet-stream\r\nAccept-Encoding: identity\r\n").utf8)
    }
}

@MainActor public protocol BackendTrafficBlobDownloadTransport {
    func stageTrafficBlob(_ manifest: TrafficBlobDownload, destination: EvidenceExportDestination, bearer: String) async throws -> EvidenceExportReceipt
}
