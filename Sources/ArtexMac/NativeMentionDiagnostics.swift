#if DEBUG
import ArtexCore
import Foundation

/// Synthetic citation records on NativeDiagnostics' fresh, private VM only.
@MainActor enum NativeMentionDiagnostics {
    static let prefix = "Native citation fixture"
    static func run(session: AuthenticationSession, directory: URL) async throws -> [Int64] {
        let service = ChatMentionService(client: AuthenticatedBackendClient(session: session))
        guard try await service.search(kind: .company, query: prefix).items.isEmpty else { throw RuntimeError.integrity("fresh citation fixture") }
        struct Created: Decodable { let id: Int64; let created: Bool }
        var ids: [Int64] = []
        for index in 1...23 {
            let body = try JSONSerialization.data(withJSONObject: ["name": prefix + String(format: " %02d", index)])
            let response = try await session.authenticatedRequest(method: "POST", path: "/api/companies", body: body)
            guard response.status == 201 else { throw RuntimeError.integrity("citation fixture creation") }
            let saved = try BackendJSONCoding.decode(Created.self, from: response.body)
            guard saved.created, saved.id > 0, !ids.contains(saved.id) else { throw RuntimeError.integrity("citation fixture identity") }
            ids.append(saved.id)
        }
        let first = try await service.search(kind: .company, query: prefix)
        guard first.items.count == 20, let cursor = first.nextCursor else { throw RuntimeError.integrity("citation first page") }
        let second = try await service.search(kind: .company, query: prefix, cursor: cursor)
        let all = first.items + second.items
        guard second.items.count == 3, second.nextCursor == nil,
              all.map(\.id) == ids.sorted(by: >), all.allSatisfy({ $0.kind == "company" && $0.label.hasPrefix(prefix) }) else { throw RuntimeError.integrity("citation page order") }
        let exact = try await service.search(kind: .company, query: String(ids.last!))
        let empty = try await service.search(kind: .company, query: "No matching synthetic citation record")
        guard exact.items.first?.id == ids.last, empty.items.isEmpty else { throw RuntimeError.integrity("citation exact and empty search") }
        let contract: [String: Any] = ["records": all.map { ["kind": $0.kind, "id": $0.id, "label": $0.label, "description": $0.description] }, "first_page": first.items.count, "second_page": second.items.count, "next_cursor_exhausted": second.nextCursor == nil, "exact_id_first": exact.items.first?.id == ids.last, "empty_search": empty.items.isEmpty]
        try JSONSerialization.data(withJSONObject: contract, options: [.prettyPrinted, .sortedKeys]).write(to: directory.appendingPathComponent("mention-contract-vm.json"))
        return ids
    }
    static func cleanup(_ ids: [Int64], session: AuthenticationSession) async throws {
        for id in ids {
            let response = try await session.authenticatedRequest(method: "DELETE", path: "/api/companies/\(id)")
            guard response.status == 200 else { throw RuntimeError.integrity("citation fixture cleanup") }
        }
        let service = ChatMentionService(client: AuthenticatedBackendClient(session: session))
        guard try await service.search(kind: .company, query: prefix).items.isEmpty else { throw RuntimeError.integrity("citation fixture cleanup verification") }
    }
}
#endif
