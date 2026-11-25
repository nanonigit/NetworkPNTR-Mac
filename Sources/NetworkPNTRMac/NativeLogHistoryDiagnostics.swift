#if DEBUG
import Foundation
import NetworkPNTRCore

@MainActor enum NativeLogHistoryDiagnostics {
    static func seed(session: AuthenticationSession, directory: URL) async throws {
        guard NativeMCPTaskDiagnostics.owns(directory: directory, requested: RuntimeFactory.diagnosticsDirectory),
              let resource = Bundle.main.url(forResource: "log_history_seed_guest", withExtension: "py",
                                             subdirectory: "Diagnostics") else {
            throw RuntimeError.integrity("private log history fixture")
        }
        let data = try Data(contentsOf: resource)
        guard ArtifactIntegrity.sha256(data) == "f0c62460dfe4192804eeb84fe3b854344a5c24ecc03e43d7abce557709b11a3d",
              let source = String(data: data, encoding: .utf8) else {
            throw RuntimeError.integrity("log history fixture resource digest")
        }
        let code = "import os\nos.environ['NETWORKPNTR_LOG_HISTORY_FIXTURE'] = '1'\n" + source
        let request = try JSONSerialization.data(withJSONObject: [
            "kind": "script", "exec": ["code": code, "timeout_ms": 20_000], "params": [:]
        ])
        let response = try await session.authenticatedRequest(method: "POST", path: "/api/tools/custom/test", body: request)
        guard response.status == 200, let result = try JSONSerialization.jsonObject(with: response.body) as? [String: Any],
              result["is_error"] as? Bool == false, let output = result["output"] as? String, output.utf8.count <= 512,
              let proof = try JSONSerialization.jsonObject(with: Data(output.utf8)) as? [String: Any],
              proof["log_fixture_seeded"] as? Bool == true, proof["rows"] as? Int == 350 else {
            throw RuntimeError.integrity("log history fixture seed receipt")
        }
    }

    static func verify(session: AuthenticationSession, directory: URL) async throws {
        let client = AuthenticatedBackendClient(session: session)
        let service = GuestLogService(client: client)
        let ring = try await service.recent(since: 0)
        guard let before = ring.items.compactMap(\.dbId).min(), before > 1_000_001 else {
            throw RuntimeError.integrity("restored log window boundary")
        }
        let first = try await service.history(before: before)
        guard first.hasMore, let next = first.items.first?.dbId else {
            throw RuntimeError.integrity("first log history page")
        }
        let second = try await service.history(before: next)
        let rows = (second.items + first.items + ring.items).filter { $0.tag == "history-review" }
        guard rows.map(\.dbId) == (1...350).map({ Optional(Int64(1_000_000 + $0)) }) else {
            throw RuntimeError.integrity("ordered log history readback")
        }
        let projection = rows.map { "\($0.dbId ?? 0)|\($0.level)|\($0.ts)|\($0.text)" }.joined(separator: "\n")
        let report: [String: Any] = [
            "fixture_rows": rows.count,
            "initial_fixture_rows": ring.items.count(where: { $0.tag == "history-review" }),
            "first_page_fixture_rows": first.items.count(where: { $0.tag == "history-review" }),
            "second_page_fixture_rows": second.items.count(where: { $0.tag == "history-review" }),
            "projection_sha256": ArtifactIntegrity.sha256(Data(projection.utf8))
        ]
        try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys])
            .write(to: directory.appendingPathComponent("native-log-history.json"), options: .atomic)
    }
}
#endif
