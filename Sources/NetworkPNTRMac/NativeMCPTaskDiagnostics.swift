#if DEBUG
import NetworkPNTRCore
import Foundation

/// Fixed developer data in the private guest; never an inbound MCP operation.
@MainActor enum NativeMCPTaskDiagnostics {
    nonisolated static func owns(directory: URL, requested: URL?) -> Bool {
        guard directory.isFileURL, let requested, requested.isFileURL else { return false }
        return directory.resolvingSymlinksInPath().standardizedFileURL.path == requested.resolvingSymlinksInPath().standardizedFileURL.path
    }

    static func seed(session: AuthenticationSession, directory: URL) async throws {
        guard owns(directory: directory, requested: RuntimeFactory.diagnosticsDirectory) else { throw RuntimeError.integrity("owned MCP task diagnostic directory") }
        let client = AuthenticatedBackendClient(session: session)
        try await NativeReviewPlan.requireNoLLM(client: client)
        let tasks = TaskService(client: client)
        guard try await tasks.list().tasks.isEmpty else { throw RuntimeError.integrity("fresh MCP task fixture") }
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let fixedSource = try String(contentsOf: root.appendingPathComponent("script/mcp_task_seed_guest.py"), encoding: .utf8)
        let code = "import os\nos.environ['NETWORKPNTR_MCP_TASK_FIXTURE'] = '1'\n" + fixedSource
        let body = try JSONSerialization.data(withJSONObject: ["kind": "script", "exec": ["code": code, "timeout_ms": 20_000], "params": [:]])
        let reply = try await session.authenticatedRequest(method: "POST", path: "/api/tools/custom/test", body: body)
        guard reply.status == 200, let result = try JSONSerialization.jsonObject(with: reply.body) as? [String: Any],
              result["is_error"] as? Bool == false, let output = result["output"] as? String,
              output.utf8.count <= 4096, let proofData = output.data(using: .utf8),
              let proof = try JSONSerialization.jsonObject(with: proofData) as? [String: Any],
              proof["mcp_task_fixture_seeded"] as? Bool == true, proof["linux_guest"] as? Bool == true,
              proof["uid"] as? Int == 1000, proof["task_ids"] as? [String] == ["7201", "7202"] else {
            throw RuntimeError.integrity("MCP terminal seed proof")
        }
        try await NativeReviewPlan.requireNoLLM(client: client)
    }

    static func collect(session: AuthenticationSession, directory: URL) async throws {
        let client = AuthenticatedBackendClient(session: session)
        try await NativeReviewPlan.requireNoLLM(client: client)
        let tasks = TaskService(client: client)
        let snapshot = try await tasks.list()
        guard Set(snapshot.tasks.map(\.id)) == ["7201", "7202"] else { throw RuntimeError.integrity("MCP terminal task IDs") }
        var reference: [[String: Any]] = []
        for (id, status, input, output) in [("7201", "done", Int64(4_294_967_294), Int64(13)), ("7202", "failed", Int64(17), Int64(5))] {
            guard let task = snapshot.tasks.first(where: { $0.id == id }) else { throw RuntimeError.integrity("MCP fixture task missing") }
            let detail = try await tasks.detail(id: id)
            guard detail.status == task.status, task.status == status, !task.paused, !task.queued,
                  task.tokens.inputTokens == input, task.tokens.outputTokens == output else {
                throw RuntimeError.integrity("MCP terminal task readback")
            }
            reference.append(["id": id, "status": status, "paused": false, "queued": false, "inputTokens": input, "outputTokens": output])
        }
        try JSONSerialization.data(withJSONObject: reference, options: [.prettyPrinted, .sortedKeys]).write(to: directory.appendingPathComponent("mcp-task-native-reference.json"), options: .atomic)
    }
}
#endif
