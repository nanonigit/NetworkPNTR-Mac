import Foundation

public enum FindingEvidenceSide: String, Sendable { case request, response }

public struct FindingTrafficSnapshot: Decodable, Sendable {
    public let id: String
    public let sourceTrafficId: String
    /// Unix seconds from the pinned traffic collector, not milliseconds.
    public let capturedAt: Int64
    public let url, method, contentType: String
    public let status: Int
    public let requestHead, responseHead, requestHash, responseHash: String
    public let requestLength, responseLength: Int64
    private enum CodingKeys: String, CodingKey {
        case id, sourceTrafficId, capturedAt, url, method, contentType, status
        case reqHead, respHead, reqHash, respHash, reqLen, respLen
    }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy:CodingKeys.self)
        id = try c.decode(String.self,forKey:.id); sourceTrafficId = try c.decode(String.self,forKey:.sourceTrafficId)
        capturedAt = try c.decode(Int64.self,forKey:.capturedAt)
        url = try c.decode(String.self,forKey:.url); method = try c.decode(String.self,forKey:.method)
        contentType = try c.decode(String.self,forKey:.contentType); status = try c.decode(Int.self,forKey:.status)
        requestHead = try c.decodeIfPresent(String.self,forKey:.reqHead) ?? ""
        responseHead = try c.decodeIfPresent(String.self,forKey:.respHead) ?? ""
        requestHash = try c.decode(String.self,forKey:.reqHash); responseHash = try c.decode(String.self,forKey:.respHash)
        requestLength = try c.decode(Int64.self,forKey:.reqLen); responseLength = try c.decode(Int64.self,forKey:.respLen)
        guard !id.isEmpty, !sourceTrafficId.isEmpty, requestLength >= 0, responseLength >= 0 else { throw BackendAPIError.invalidResponse }
    }
}

public struct FindingTrafficBinding: Decodable, Sendable {
    public let id, findingId, snapshotId, role, note, createdAt: String
    public let position: Int
    public let snapshot: FindingTrafficSnapshot
    private enum CodingKeys: String, CodingKey { case id, findingId, snapshotId, role, note, createdAt, position, snapshot }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy:CodingKeys.self)
        id = try c.decode(String.self,forKey:.id); findingId = try c.decode(String.self,forKey:.findingId)
        snapshotId = try c.decode(String.self,forKey:.snapshotId); role = try c.decode(String.self,forKey:.role)
        note = try c.decode(String.self,forKey:.note); createdAt = try c.decode(String.self,forKey:.createdAt)
        position = try c.decode(Int.self,forKey:.position); snapshot = try c.decode(FindingTrafficSnapshot.self,forKey:.snapshot)
        try FindingWire.validateID(id); try FindingWire.validateID(findingId)
        guard position >= 0, Data(snapshotId.utf8) == Data(snapshot.id.utf8) else { throw BackendAPIError.invalidResponse }
    }
}

public struct FindingTraffic: Decodable, Sendable {
    public let findingId: String
    public let version, reportVersion: Int64
    public let bindings: [FindingTrafficBinding]
    private enum CodingKeys: String, CodingKey { case findingId, version, reportVersion, bindings }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy:CodingKeys.self)
        findingId = try c.decode(String.self,forKey:.findingId)
        version = try c.decode(Int64.self,forKey:.version); reportVersion = try c.decode(Int64.self,forKey:.reportVersion)
        bindings = try FindingWire.array(FindingTrafficBinding.self,in:c,key:.bindings)
        try FindingWire.validateID(findingId)
        guard version >= 0, reportVersion >= 0, bindings.allSatisfy({$0.findingId == findingId}),
              Set(bindings.map(\.id)).count == bindings.count else { throw BackendAPIError.invalidResponse }
    }
}

/// Offsets describe consumed original bytes, not the UTF8 length of replacement/binary display text.
public struct FindingEvidencePreview: Decodable, Sendable {
    public let content: String
    public let offset, total, nextOffset: Int64
    public let truncated, binary: Bool
    private enum CodingKeys: String, CodingKey { case content, offset, total, nextOffset, truncated, binary }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy:CodingKeys.self)
        content = try c.decode(String.self,forKey:.content)
        offset = try c.decode(Int64.self,forKey:.offset); total = try c.decode(Int64.self,forKey:.total)
        nextOffset = try c.decode(Int64.self,forKey:.nextOffset)
        truncated = try c.decode(Bool.self,forKey:.truncated); binary = try c.decode(Bool.self,forKey:.binary)
        guard offset >= 0, total >= offset, nextOffset >= offset, nextOffset <= total,
              nextOffset-offset <= 8192, truncated == (nextOffset < total), !truncated || nextOffset > offset else {
            throw BackendAPIError.invalidResponse
        }
    }
}

public struct FindingTrafficDetail: Decodable, Sendable {
    public let binding: FindingTrafficBinding
    public let request, response: FindingEvidencePreview
    private enum CodingKeys: String, CodingKey { case binding, request, response }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy:CodingKeys.self)
        binding = try c.decode(FindingTrafficBinding.self,forKey:.binding)
        request = try c.decode(FindingEvidencePreview.self,forKey:.request)
        response = try c.decode(FindingEvidencePreview.self,forKey:.response)
        guard request.offset == 0, response.offset == 0, request.total == binding.snapshot.requestLength,
              response.total == binding.snapshot.responseLength else { throw BackendAPIError.invalidResponse }
    }
}
