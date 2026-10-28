import Foundation

public enum EvidenceExportError: Error, Sendable { case invalidDestination, destinationExists, invalidManifest, integrity, storage, cleanupRequired }

/// Immutable body identity and fixed guest route; no guest filename or destination URL is accepted.
public struct FindingEvidenceDownload: Sendable {
    public let findingID, bindingID: String
    public let side: FindingEvidenceSide
    public let expectedSize: Int64
    public let expectedSHA256: String
    public let contextTaskID: String?
    public var suggestedFilename: String { "evidence-\(bindingID)-\(side.rawValue).bin" }
    public init(findingID: String, bindingID: String, side: FindingEvidenceSide, expectedSize: Int64, expectedSHA256: String, contextTaskID: String? = nil) throws {
        self.findingID = try FindingWire.canonicalID(findingID); self.bindingID = try FindingWire.canonicalID(bindingID)
        self.contextTaskID = try contextTaskID.map(FindingWire.canonicalID)
        guard expectedSize >= 0, expectedSHA256.utf8.count == 64,
              expectedSHA256.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else { throw EvidenceExportError.invalidManifest }
        self.side = side; self.expectedSize = expectedSize; self.expectedSHA256 = expectedSHA256
    }
    public init(binding: FindingTrafficBinding, side: FindingEvidenceSide, contextTaskID: String? = nil) throws {
        try self.init(findingID: binding.findingId, bindingID: binding.id, side: side,
                      expectedSize: side == .request ? binding.snapshot.requestLength : binding.snapshot.responseLength,
                      expectedSHA256: side == .request ? binding.snapshot.requestHash : binding.snapshot.responseHash, contextTaskID: contextTaskID)
    }
    func request(bearer: String) throws -> Data {
        let path = "/api/exploration/findings/" + findingID + "/traffic/" + bindingID + "/body?side=" + side.rawValue + "&download=1" + (contextTaskID.map { "&context_task=" + $0 } ?? "")
        let base = try BackendHTTPRequest.make(method: "GET", path: path, body: nil, bearer: bearer)
        guard !bearer.isEmpty else { throw BackendAPIError.invalidResponse }
        return Data(String(decoding: base, as: UTF8.self).replacingOccurrences(of: "Accept: application/json\r\n", with: "Accept: application/octet-stream\r\nAccept-Encoding: identity\r\n").utf8)
    }
}
