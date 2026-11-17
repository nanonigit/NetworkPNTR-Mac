import Foundation

public enum TrafficSort: String, Sendable, CaseIterable { case timestamp = "ts", status, responseLength = "resp_len" }
public enum TrafficSortOrder: String, Sendable, CaseIterable { case ascending = "asc", descending = "desc" }
public enum TrafficStatusFilter: Sendable {
    case informational, success, redirect, clientError, serverError, exact(Int64)
    var wire: String {
        switch self {
        case .informational: "1xx"
        case .success: "2xx"
        case .redirect: "3xx"
        case .clientError: "4xx"
        case .serverError: "5xx"
        case .exact(let value): String(value)
        }
    }
}

/// Applied traffic filters. UI draft parsing/debounce is separate; values never become destinations.
public struct TrafficQuery: Sendable {
    public var page: Int64 = 0
    public var size = 50
    public var host = "", keyword = "", body = "", path = ""
    public var method: CapturedHTTPMethod?
    public var status: TrafficStatusFilter?
    public var responseMinimum: Int64?, responseMaximum: Int64?
    public var sort: TrafficSort = .timestamp
    public var order: TrafficSortOrder = .descending
    public init() {}
    func pathString() throws -> String {
        guard page >= 0, (1...500).contains(size), page <= Int64.max/Int64(size),
              [host,keyword,body,path].allSatisfy({ $0.utf8.count<=8192 }),
              responseMinimum.map({$0>=0}) ?? true, responseMaximum.map({$0>=0}) ?? true else {throw FindingInputError.query}
        var items=[URLQueryItem(name:"page",value:String(page)),.init(name:"size",value:String(size))]
        for (name,value) in [("host",host),("q",keyword),("body",body),("path",path)] where !value.isEmpty {items.append(.init(name:name,value:value))}
        if let method {items.append(.init(name:"method",value:method.rawValue))}
        if let status {items.append(.init(name:"status",value:status.wire))}
        if let responseMinimum {items.append(.init(name:"resp_min",value:String(responseMinimum)))}
        if let responseMaximum {items.append(.init(name:"resp_max",value:String(responseMaximum)))}
        items.append(contentsOf:[.init(name:"sort",value:sort.rawValue),.init(name:"order",value:order.rawValue)])
        return try CapturedTrafficWire.path("/api/traffic",items:items)
    }
}

public struct TrafficHost: Decodable, Sendable {
    public let host: String
    public let count: Int64
    public var identity: Data {Data(host.utf8)}
    private enum CodingKeys: String,CodingKey {case host,count}
    public init(from decoder: any Decoder) throws {
        let c=try decoder.container(keyedBy:CodingKeys.self)
        host=try c.decode(String.self,forKey:.host);count=try c.decode(Int64.self,forKey:.count)
        guard count>=0,host.utf8.count<=8192 else {throw BackendAPIError.invalidResponse}
    }
}
public struct TrafficHosts: Decodable, Sendable {
    public let hosts:[TrafficHost]
    private enum CodingKeys:String,CodingKey {case hosts}
    public init(from decoder:any Decoder) throws {
        let c=try decoder.container(keyedBy:CodingKeys.self)
        guard c.contains(.hosts) else {throw BackendAPIError.invalidResponse}
        hosts=try c.decodeIfPresent([TrafficHost].self,forKey:.hosts) ?? []
        guard Set(hosts.map(\.identity)).count==hosts.count else {throw BackendAPIError.invalidResponse}
    }
}
public struct TrafficCaptureSettings: Decodable, Sendable {public let trafficCapture:Bool}
public struct TrafficDeletionReceipt: Decodable, Sendable {
    public let deleted:Int64
    public let reclaimed:Int64?
    private enum CodingKeys:String,CodingKey {case deleted,reclaimed}
    public init(from decoder:any Decoder) throws {
        let c=try decoder.container(keyedBy:CodingKeys.self)
        deleted=try c.decode(Int64.self,forKey:.deleted);reclaimed=try c.decodeIfPresent(Int64.self,forKey:.reclaimed)
        guard deleted>=0,reclaimed.map({$0>=0}) ?? true else {throw BackendAPIError.invalidResponse}
    }
}
public enum TrafficMutation: Sendable {
    case deleteMatchingHost(String),deleteHosts([String]),purgeAll,capture(Bool)
}
public enum TrafficMutationReceipt: Sendable {
    case deleted(TrafficDeletionReceipt),capture(TrafficCaptureSettings)
}
