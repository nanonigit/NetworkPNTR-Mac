import Foundation

public struct FindingGroup: Decodable, Sendable {
    public let taskId: String?
    public let taskName: String
    public let taskDescription: String
    public let taskStatus: String
    public let count: Int64
    public let critical: Int64, high: Int64, medium: Int64, low: Int64
    public let lastFoundAt: String
    private enum CodingKeys: String, CodingKey { case taskId, taskName, taskDescription, taskStatus, count, critical, high, medium, low, lastFoundAt }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy:CodingKeys.self)
        guard c.contains(.taskId) else { throw BackendAPIError.invalidResponse }
        taskId = try c.decodeIfPresent(FindingWire.ID.self,forKey:.taskId)?.value
        taskName = try c.decodeIfPresent(String.self,forKey:.taskName) ?? ""
        taskDescription = try c.decode(String.self,forKey:.taskDescription); taskStatus = try c.decode(String.self,forKey:.taskStatus)
        count = try c.decode(Int64.self,forKey:.count); critical = try c.decode(Int64.self,forKey:.critical); high = try c.decode(Int64.self,forKey:.high)
        medium = try c.decode(Int64.self,forKey:.medium); low = try c.decode(Int64.self,forKey:.low); lastFoundAt = try c.decode(String.self,forKey:.lastFoundAt)
        guard [count,critical,high,medium,low].allSatisfy({$0 >= 0}) else { throw BackendAPIError.invalidResponse }
    }
}
public struct FindingGroupsPage: Decodable, Sendable {
    public let items: [FindingGroup]
    public let total: Int64, findingTotal: Int64, page: Int64
    public let pageSize: Int
    private enum CodingKeys: String, CodingKey { case items, total, findingTotal, page, pageSize }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy:CodingKeys.self)
        items = try FindingWire.array(FindingGroup.self,in:c,key:.items)
        total = try c.decode(Int64.self,forKey:.total); findingTotal = try c.decode(Int64.self,forKey:.findingTotal)
        page = try c.decode(Int64.self,forKey:.page); pageSize = try c.decode(Int.self,forKey:.pageSize)
        guard total >= 0, findingTotal >= 0, page > 0, (1...100).contains(pageSize), items.count <= pageSize,
              Set(items.map(\.taskId)).count == items.count else { throw BackendAPIError.invalidResponse }
    }
}
public struct FindingTaskOption: Decodable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let description: String
    public let count: Int64
    private enum CodingKeys: String, CodingKey { case id, name, description, count }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy:CodingKeys.self)
        id = try c.decode(FindingWire.ID.self,forKey:.id).value; name = try c.decodeIfPresent(String.self,forKey:.name) ?? ""
        description = try c.decode(String.self,forKey:.description); count = try c.decode(Int64.self,forKey:.count)
        guard count >= 0 else { throw BackendAPIError.invalidResponse }
    }
}
public struct FindingStats: Decodable, Sendable {
    public let total: Int64, pending: Int64, critical: Int64, high: Int64, medium: Int64, low: Int64
    public let vulnclasses: [String]
    public let tasks: [FindingTaskOption]
    private enum CodingKeys: String, CodingKey { case total, pending, critical, high, medium, low, vulnclasses, tasks }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy:CodingKeys.self)
        total = try c.decode(Int64.self,forKey:.total); pending = try c.decode(Int64.self,forKey:.pending)
        critical = try c.decode(Int64.self,forKey:.critical); high = try c.decode(Int64.self,forKey:.high)
        medium = try c.decode(Int64.self,forKey:.medium); low = try c.decode(Int64.self,forKey:.low)
        vulnclasses = try FindingWire.array(String.self,in:c,key:.vulnclasses); tasks = try FindingWire.array(FindingTaskOption.self,in:c,key:.tasks)
        guard [total,pending,critical,high,medium,low].allSatisfy({$0 >= 0}), Set(tasks.map(\.id)).count == tasks.count else { throw BackendAPIError.invalidResponse }
    }
}
public struct FindingAssetNode: Decodable, Sendable {
    public let key: String
    public let parent: String?
    public let kind: String
    public let label: String
    public let assetId: Int64?, companyId: Int64?
    public let selfCount: Int64, total: Int64, critical: Int64, high: Int64, medium: Int64, low: Int64
    public let lastFoundAt: String
    public var identity: Data { Data(key.utf8) }
    private enum CodingKeys: String, CodingKey { case key, parent, kind, label, assetId, companyId, selfCount = "self", total, critical, high, medium, low, lastFoundAt }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy:CodingKeys.self)
        key = try c.decode(String.self,forKey:.key); parent = try c.decodeIfPresent(String.self,forKey:.parent)
        kind = try c.decode(String.self,forKey:.kind); label = try c.decode(String.self,forKey:.label)
        assetId = try c.decodeIfPresent(Int64.self,forKey:.assetId); companyId = try c.decodeIfPresent(Int64.self,forKey:.companyId)
        selfCount = try c.decode(Int64.self,forKey:.selfCount); total = try c.decode(Int64.self,forKey:.total)
        critical = try c.decode(Int64.self,forKey:.critical); high = try c.decode(Int64.self,forKey:.high)
        medium = try c.decode(Int64.self,forKey:.medium); low = try c.decode(Int64.self,forKey:.low); lastFoundAt = try c.decode(String.self,forKey:.lastFoundAt)
        guard !key.isEmpty, [assetId,companyId].compactMap({$0}).allSatisfy({$0 > 0}),
              [selfCount,total,critical,high,medium,low].allSatisfy({$0 >= 0}), selfCount <= total else { throw BackendAPIError.invalidResponse }
    }
}
public struct FindingAssetTree: Decodable, Sendable {
    public let nodes: [FindingAssetNode]
    public let findingTotal: Int64
    public let truncated: Bool
    public let droppedKinds: [String]
    private enum CodingKeys: String, CodingKey { case nodes, findingTotal, truncated, droppedKinds }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy:CodingKeys.self)
        nodes = try FindingWire.array(FindingAssetNode.self,in:c,key:.nodes); findingTotal = try c.decode(Int64.self,forKey:.findingTotal)
        truncated = try c.decode(Bool.self,forKey:.truncated); droppedKinds = try c.decodeIfPresent([String].self,forKey:.droppedKinds) ?? []
        let keys = Set(nodes.map(\.identity))
        guard findingTotal >= 0, keys.count == nodes.count else { throw BackendAPIError.invalidResponse }
        var parents: [Data:Data] = [:]
        for node in nodes {
            if let parent = node.parent, !parent.isEmpty {
                let value = Data(parent.utf8); guard keys.contains(value) else { throw BackendAPIError.invalidResponse }
                parents[node.identity] = value
            }
        }
        var complete = Set<Data>()
        for key in keys where !complete.contains(key) {
            var path = Set<Data>(), cursor: Data? = key
            while let current = cursor, !complete.contains(current) {
                guard path.insert(current).inserted else { throw BackendAPIError.invalidResponse }
                cursor = parents[current]
            }
            complete.formUnion(path)
        }
    }
}
