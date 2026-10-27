import Foundation

/// Fixed evidence routes with captured mutation ownership; no arbitrary destination or caller credential.
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
    private func read<T: Decodable>(_ type: T.Type,path: String,method: String = "GET",body: Data? = nil) async throws -> T {
        try Task.checkCancellation()
        let response = try await client.send(method:method,path:path,body:body,bearer:nil)
        try Task.checkCancellation()
        guard (200..<300).contains(response.status) else { throw BackendAPIError.status(response.status) }
        guard response.status == 200, response.body.count <= 4 * 1024 * 1024 else { throw BackendAPIError.invalidResponse }
        return try BackendJSONCoding.decode(type,from:response.body)
    }
}

public enum FindingTrafficRole: String, Encodable, CaseIterable, Sendable {
    case baseline, proof, verification, supporting
}
public struct FindingTrafficRef: Encodable, Sendable {
    public let trafficId: String
    public let role: FindingTrafficRole
    public let note: String
    public init(trafficId: String,role: FindingTrafficRole = .supporting,note: String = "") {
        self.trafficId = trafficId; self.role = role; self.note = note
    }
}
public enum FindingTrafficChange: Sendable {
    case bind([FindingTrafficRef])
    case edit(bindingID: String,role: FindingTrafficRole,note: String)
    case remove(bindingID: String)
    case reorder([String])
}

struct FindingTrafficWriteRequest {
    let owner, method, path: String
    let body: Data
    let previousVersion: Int64
}

extension FindingTrafficService {
    /// A thrown post-dispatch error is not proof of rollback; the caller owns uncertainty and must not retry automatically.
    public func apply(_ change: FindingTrafficChange,to target: FindingRecord,snapshot: FindingTraffic,
                      contextTaskID: String? = nil) async throws -> FindingTraffic {
        try await execute(prepare(change,to:target,snapshot:snapshot,contextTaskID:contextTaskID))
    }
    func prepare(_ change: FindingTrafficChange,to target: FindingRecord,snapshot: FindingTraffic,
                 contextTaskID: String? = nil) throws -> FindingTrafficWriteRequest {
        try Task.checkCancellation()
        guard target.canMutate, let handle = target.findingId else { throw FindingInputError.readOnly }
        let owner = try FindingWire.canonicalID(handle)
        guard snapshot.findingId == owner else { throw FindingInputError.patch }
        if let contextTaskID {
            guard try FindingWire.canonicalID(contextTaskID) == target.taskId else { throw FindingInputError.readOnly }
        }
        let members = Set(snapshot.bindings.map(\.id))
        func member(_ id: String) throws -> String {
            let canonical = try FindingWire.canonicalID(id)
            guard members.contains(canonical) else { throw FindingInputError.patch }; return canonical
        }
        let method: String, suffix: String, body: Data
        switch change {
        case .bind(let refs):
            guard !refs.isEmpty, refs.allSatisfy({!FindingWire.serverTrim($0.trafficId).isEmpty}) else { throw FindingInputError.patch }
            struct Body: Encodable { let trafficRefs: [FindingTrafficRef] }
            method = "POST"; suffix = ""; body = try BackendJSONCoding.encode(Body(trafficRefs:refs))
        case .edit(let id,let role,let note):
            struct Body: Encodable { let version: Int64; let role: FindingTrafficRole; let note: String }
            method = "PATCH"; suffix = "/"+(try member(id))
            body = try BackendJSONCoding.encode(Body(version:snapshot.version,role:role,note:note))
        case .remove(let id):
            struct Body: Encodable { let version: Int64 }
            method = "DELETE"; suffix = "/"+(try member(id))
            body = try BackendJSONCoding.encode(Body(version:snapshot.version))
        case .reorder(let ids):
            let canonical = try ids.map(member)
            guard canonical.count == members.count, Set(canonical) == members else { throw FindingInputError.patch }
            struct Body: Encodable { let version: Int64; let bindingIds: [String] }
            method = "PUT"; suffix = "/order"
            body = try BackendJSONCoding.encode(Body(version:snapshot.version,bindingIds:canonical))
        }
        guard body.count <= 1024 * 1024 else { throw FindingInputError.bodyLimit }
        return .init(owner:owner,method:method,path:try route(owner:owner,suffix:suffix,context:contextTaskID),body:body,previousVersion:snapshot.version)
    }
    func execute(_ request: FindingTrafficWriteRequest) async throws -> FindingTraffic {
        let value = try await read(FindingTraffic.self,path:request.path,method:request.method,body:request.body)
        guard value.findingId == request.owner, value.version >= request.previousVersion,
              request.method == "POST" || value.version > request.previousVersion else {
            throw BackendAPIError.invalidResponse
        }
        return value
    }
}
