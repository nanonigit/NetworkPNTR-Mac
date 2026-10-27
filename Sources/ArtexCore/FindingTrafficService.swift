import Foundation

/// Read-only evidence capability; no arbitrary destination, credential or mutation route.
@MainActor public struct FindingTrafficService {
    private let client: any BackendJSONTransport
    public init(client: any BackendJSONTransport) { self.client = client }
    public func list(findingID: String,contextTaskID: String? = nil) async throws -> FindingTraffic {
        let owner = try FindingWire.canonicalID(findingID)
        let result = try await read(FindingTraffic.self,path:route(owner:owner,context:contextTaskID))
        guard result.findingId == owner else { throw BackendAPIError.invalidResponse }; return result
    }
    public func detail(findingID: String,bindingID: String,contextTaskID: String? = nil) async throws -> FindingTrafficDetail {
        let owner = try FindingWire.canonicalID(findingID), binding = try FindingWire.canonicalID(bindingID)
        let result = try await read(FindingTrafficDetail.self,path:route(owner:owner,suffix:"/"+binding,context:contextTaskID))
        guard result.binding.findingId == owner, result.binding.id == binding else { throw BackendAPIError.invalidResponse }; return result
    }
    public func body(findingID: String,bindingID: String,side: FindingEvidenceSide,offset: Int64,
                     contextTaskID: String? = nil) async throws -> FindingEvidencePreview {
        let owner = try FindingWire.canonicalID(findingID), binding = try FindingWire.canonicalID(bindingID)
        guard offset >= 0 else { throw FindingInputError.query }
        let path = try route(owner:owner,suffix:"/"+binding+"/body",context:contextTaskID,
                             query:["side="+side.rawValue,"offset="+String(offset)])
        let result = try await read(FindingEvidencePreview.self,path:path)
        guard result.offset == offset else { throw BackendAPIError.invalidResponse }; return result
    }
    private func route(owner: String,suffix: String = "",context: String?,query: [String] = []) throws -> String {
        var parts = query
        if let context { parts.append("context_task="+(try FindingWire.canonicalID(context))) }
        return "/api/exploration/findings/"+owner+"/traffic"+suffix+(parts.isEmpty ? "" : "?"+parts.joined(separator:"&"))
    }
    private func read<T: Decodable>(_ type: T.Type,path: String) async throws -> T {
        try Task.checkCancellation()
        let response = try await client.send(method:"GET",path:path,body:nil,bearer:nil)
        try Task.checkCancellation()
        guard (200..<300).contains(response.status) else { throw BackendAPIError.status(response.status) }
        guard response.status == 200, response.body.count <= 4 * 1024 * 1024 else { throw BackendAPIError.invalidResponse }
        return try BackendJSONCoding.decode(type,from:response.body)
    }
}
