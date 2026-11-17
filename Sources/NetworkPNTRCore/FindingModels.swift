import Foundation

public enum FindingSeverity: String, CaseIterable, Encodable, Sendable { case critical, high, medium, low }
public enum FindingStatus: String, CaseIterable, Encodable, Sendable {
    case pending, inProgress = "in_progress", confirmed, resolved, fixed, falsePositive = "false_positive", ignored, duplicate, riskAccepted = "risk_accepted"
}
public struct FindingAsset: Decodable, Sendable, Equatable, Identifiable {
    public let id: String
    public let type: String
    public let label: String
}
public struct FindingRowIdentity: Hashable, Sendable {
    public let taskId: String?
    public let id: String
}

/// A task's node ID and the standalone finding mutation handle are deliberately distinct.
public struct FindingRecord: Decodable, Sendable, Identifiable {
    public let id: String
    public let findingId: String?
    public let name: String
    public let vulnclass: String
    public let severity: String
    public let status: String
    public let summary: String
    public let evidence: String
    public let report: String
    public let intentId: String?
    public let paramId: String?
    public let taskId: String?
    public let taskDescription: String
    public let sourceTaskId: String?
    public let inherited: Bool
    public let assets: [FindingAsset]
    public let ts: String
    public let trafficCount: Int64
    public let evidenceVersion: Int64
    public let reportEvidenceVersion: Int64
    public let reportStale: Bool
    public var canMutate: Bool { !inherited && findingId != nil }
    public var identity: FindingRowIdentity { .init(taskId:taskId,id:id) }
    var standalone: Bool { findingId == id }
    private enum CodingKeys: String, CodingKey {
        case id, findingId, name, vulnclass, severity, status, summary, evidence, report, intentId, paramId, taskId, taskDescription
        case sourceTaskId, inherited, assets, ts, trafficCount, evidenceVersion, reportEvidenceVersion, reportStale
    }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy:CodingKeys.self)
        id = try c.decode(String.self,forKey:.id); findingId = try c.decodeIfPresent(String.self,forKey:.findingId)
        name = try c.decodeIfPresent(String.self,forKey:.name) ?? ""; vulnclass = try c.decode(String.self,forKey:.vulnclass)
        severity = try c.decode(String.self,forKey:.severity); status = try c.decode(String.self,forKey:.status)
        summary = try c.decode(String.self,forKey:.summary); evidence = try c.decode(String.self,forKey:.evidence)
        report = try c.decodeIfPresent(String.self,forKey:.report) ?? ""
        intentId = try c.decodeIfPresent(String.self,forKey:.intentId); paramId = try c.decodeIfPresent(String.self,forKey:.paramId)
        taskId = try c.decodeIfPresent(String.self,forKey:.taskId); taskDescription = try c.decodeIfPresent(String.self,forKey:.taskDescription) ?? ""
        sourceTaskId = try c.decodeIfPresent(String.self,forKey:.sourceTaskId); inherited = try c.decodeIfPresent(Bool.self,forKey:.inherited) ?? false
        assets = try c.decodeIfPresent([FindingAsset].self,forKey:.assets) ?? []; ts = try c.decode(String.self,forKey:.ts)
        trafficCount = try c.decodeIfPresent(Int64.self,forKey:.trafficCount) ?? 0
        evidenceVersion = try c.decodeIfPresent(Int64.self,forKey:.evidenceVersion) ?? 0
        reportEvidenceVersion = try c.decodeIfPresent(Int64.self,forKey:.reportEvidenceVersion) ?? 0
        reportStale = try c.decodeIfPresent(Bool.self,forKey:.reportStale) ?? false
        try FindingWire.validateID(id)
        for value in [findingId,intentId,paramId,taskId,sourceTaskId].compactMap({$0}) { try FindingWire.validateID(value) }
        for asset in assets { try FindingWire.validateID(asset.id) }
        guard [trafficCount,evidenceVersion,reportEvidenceVersion].allSatisfy({$0 >= 0}), Set(assets.map(\.id)).count == assets.count,
              !inherited || sourceTaskId != nil && sourceTaskId == taskId else { throw BackendAPIError.invalidResponse }
    }
}
public struct FindingPage: Decodable, Sendable {
    public internal(set) var items: [FindingRecord]
    public internal(set) var total: Int64
    public let page: Int64
    public let pageSize: Int
    private enum CodingKeys: String, CodingKey { case items, total, page, pageSize }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy:CodingKeys.self)
        items = try FindingWire.array(FindingRecord.self,in:c,key:.items)
        total = try c.decode(Int64.self,forKey:.total); page = try c.decode(Int64.self,forKey:.page); pageSize = try c.decode(Int.self,forKey:.pageSize)
        guard total >= 0, page > 0, (1...200).contains(pageSize), items.count <= pageSize,
              Set(items.map(\.id)).count == items.count else { throw BackendAPIError.invalidResponse }
    }
}
public struct FindingDeletion: Decodable, Sendable {
    public let deleted: Bool
    public let id: Int64
}

enum FindingWire {
    struct ID: Decodable {
        let value: String
        init(from decoder: any Decoder) throws {
            let c = try decoder.singleValueContainer()
            if let raw = try? c.decode(String.self) { value = raw } else { value = String(try c.decode(Int64.self)) }
            try validateID(value)
        }
    }
    static func canonicalID(_ value: String) throws -> String {
        guard !value.isEmpty, value.utf8.allSatisfy({(48...57).contains($0)}), let number = Int64(value), number > 0 else { throw FindingInputError.invalidID }
        return String(number)
    }
    static func validateID(_ value: String) throws {
        guard let canonical = try? canonicalID(value), canonical == value else { throw BackendAPIError.invalidResponse }
    }
    static func array<T: Decodable,K: CodingKey>(_ type: T.Type,in container: KeyedDecodingContainer<K>,key: K) throws -> [T] {
        guard container.contains(key) else { throw BackendAPIError.invalidResponse }
        return try container.decodeIfPresent([T].self,forKey:key) ?? []
    }
    /// Go TrimSpace differs from browser trim at NEL and FEFF; apply only to confirmed edited fields.
    static func serverTrim(_ input: String) -> String {
        func space(_ c: Unicode.Scalar) -> Bool { (9...13).contains(c.value) || [32,0x85,0xA0,0x1680,0x2028,0x2029,0x202F,0x205F,0x3000].contains(c.value) || (0x2000...0x200A).contains(c.value) }
        var values = input.unicodeScalars
        while let first = values.first, space(first) { values.removeFirst() }
        while let last = values.last, space(last) { values.removeLast() }
        return String(values)
    }
}
