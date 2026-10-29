import Foundation

/// Fixed finite API operations. A post-dispatch failure is never a rollback or permission to replay.
@MainActor public struct TrafficService {
    private let client:any BackendJSONTransport
    public init(client:any BackendJSONTransport) {self.client=client}
    public func list(_ query:TrafficQuery = .init()) async throws -> CapturedTrafficPage {
        let result=try await read(CapturedTrafficPage.self,path:query.pathString())
        guard result.isUnavailable || (result.page==query.page && result.size==query.size) else {throw BackendAPIError.invalidResponse}
        return result
    }
    public func blobDownload(id: String, side: FindingEvidenceSide) async throws -> TrafficBlobDownload {
        try CapturedTrafficWire.validateID(id)
        let path = try CapturedTrafficWire.path("/api/traffic/blob-metadata", items: [.init(name: "id", value: id), .init(name: "side", value: side.rawValue)])
        let value = try await read(TrafficBlobDownload.self, path: path)
        guard value.identity == Data(id.utf8), value.side == side else { throw BackendAPIError.invalidResponse }
        return value
    }
    public func hosts() async throws -> TrafficHosts {try await read(TrafficHosts.self,path:"/api/traffic/hosts")}
    public func captureSettings() async throws -> TrafficCaptureSettings {try await read(TrafficCaptureSettings.self,path:"/api/settings")}
    public func detail(id:String) async throws -> CapturedTrafficDetail {try await CapturedTrafficService(client:client).detail(id:id)}

    public func apply(_ change:TrafficMutation,onDispatch:@MainActor () throws -> Void = {}) async throws -> TrafficMutationReceipt {
        try await execute(prepare(change),onDispatch:onDispatch)
    }
    func prepare(_ change:TrafficMutation) throws -> TrafficWriteRequest {
        try Task.checkCancellation()
        let method:String,path:String,body:Data?
        switch change {
        case .deleteMatchingHost(let host):
            try validate(host)
            guard !FindingWire.serverTrim(host).isEmpty else {throw FindingInputError.query}
            method="DELETE";path=try CapturedTrafficWire.path("/api/traffic",items:[.init(name:"host",value:host)]);body=nil
        case .deleteHosts(let hosts):
            for host in hosts {try validate(host)}
            guard hosts.contains(where:{!FindingWire.serverTrim($0).isEmpty}) else {throw FindingInputError.query}
            struct Body:Encodable {let hosts:[String]}
            method="DELETE";path="/api/traffic/hosts";body=try BackendJSONCoding.encode(Body(hosts:hosts))
        case .purgeAll:
            method="DELETE";path="/api/traffic/all";body=nil
        case .capture(let value):
            struct Body:Encodable {let trafficCapture:Bool}
            method="PUT";path="/api/settings";body=try BackendJSONCoding.encode(Body(trafficCapture:value))
        }
        guard body.map({$0.count<=1024*1024}) ?? true else {throw FindingInputError.bodyLimit}
        return TrafficWriteRequest(method:method,path:path,body:body,change:change)
    }
    func execute(_ prepared:TrafficWriteRequest,onDispatch:@MainActor () throws -> Void) async throws -> TrafficMutationReceipt {
        let raw=try await request(method:prepared.method,path:prepared.path,body:prepared.body,onDispatch:onDispatch)
        if case .capture(let expected)=prepared.change {
            let settings=try BackendJSONCoding.decode(TrafficCaptureSettings.self,from:raw)
            guard settings.trafficCapture==expected else {throw BackendAPIError.invalidResponse}
            return .capture(settings)
        }
        let receipt=try BackendJSONCoding.decode(TrafficDeletionReceipt.self,from:raw)
        if case .purgeAll=prepared.change {guard receipt.reclaimed != nil else {throw BackendAPIError.invalidResponse}}
        return .deleted(receipt)
    }
    private func validate(_ host:String) throws {guard host.utf8.count<=8192 else {throw FindingInputError.query}}
    private func read<T:Decodable>(_ type:T.Type,path:String) async throws -> T {
        try await BackendJSONCoding.decode(type,from:request(method:"GET",path:path,body:nil,onDispatch:{}))
    }
    private func request(method:String,path:String,body:Data?,onDispatch:@MainActor () throws -> Void) async throws -> Data {
        try Task.checkCancellation();try onDispatch();try Task.checkCancellation()
        let response=try await client.send(method:method,path:path,body:body,bearer:nil)
        try Task.checkCancellation()
        guard response.status==200 else {throw BackendAPIError.status(response.status)}
        guard response.body.count<=4*1024*1024 else {throw BackendAPIError.invalidResponse}
        return response.body
    }
}

struct TrafficWriteRequest:Sendable {
    let method:String,path:String
    let body:Data?
    let change:TrafficMutation
}
