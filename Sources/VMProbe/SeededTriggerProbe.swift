#if DEBUG
import ArtexCore
import Foundation

@MainActor enum SeededTriggerProbe {
    enum Kind: String {
        case finding, goal, tool

        var state: String { self == .finding ? "confirmed" : "met" }
        var prompt: String {
            switch self {
            case .finding: CloudEgressVMFixture.findingPrompt
            case .goal: CloudEgressVMFixture.goalPrompt
            case .tool: CloudEgressVMFixture.toolPrompt
            }
        }

        func matches(_ rule: AgentTriggerRule) -> Bool {
            switch self {
            case .finding: rule.onFinding
            case .goal: rule.onGoalMet
            case .tool: rule.onToolCall
            }
        }
        var summary: String {
            self == .finding ? CloudEgressVMFixture.currentFindingSummary : CloudEgressVMFixture.currentGoalSummary
        }

        func replyCount(_ fixture: CloudEgressVMFixture) -> Int {
            switch self {
            case .finding: fixture.snapshot.findingReplies
            case .goal: fixture.snapshot.goalReplies
            case .tool: fixture.snapshot.toolReplies
            }
        }
    }
    private enum Event: String { case historical, unmatched, pending, current }

    static func verify(_ kind: Kind, client: AuthenticatedBackendClient, chat: ChatService, fixture: CloudEgressVMFixture) async throws {
        let service = AgentCatalogService(client: client)
        guard let agent = try await service.list().first(where: { $0.key == "reporter" && !$0.builtin }) else {
            throw RuntimeError.integrity("seeded trigger fixture owner")
        }
        let baseline = try await service.triggers(for: agent)
        let ids = Set(baseline.map(\.id))
        let conversationIDs = Set(try await chat.conversations().map(\.id))
        let defaults = baseline.filter { $0.rule.enabled && kind.matches($0.rule) }
        for row in defaults {
            _ = try await service.setTriggerEnabled(for: agent, id: row.id, enabled: false)
        }
        // Keep one enabled unrelated rule so the pinned scheduler advances event state.
        var sentinel = AgentTriggerRule()
        sentinel.onToolCall = true
        sentinel.toolNames = ["nonexistent_fixture_tool"]
        let armed = try await service.createTrigger(for: agent, rule: sentinel)
        guard let sentinelRow = armed.first(where: { !ids.contains($0.id) }) else {
            throw RuntimeError.integrity("seeded trigger sentinel")
        }

        var rule = AgentTriggerRule()
        rule.enabled = false
        switch kind {
        case .finding: rule.onFinding = true; rule.findingMessage = kind.prompt
        case .goal: rule.onGoalMet = true; rule.goalMessage = kind.prompt
        case .tool:
            rule.onToolCall = true
            rule.toolCallMessage = kind.prompt
            rule.toolNames = ["fixture_selected_tool"]
        }
        let rows = try await service.createTrigger(for: agent, rule: rule)
        guard let row = rows.first(where: { !ids.contains($0.id) && $0.id != sentinelRow.id }) else {
            throw RuntimeError.integrity("seeded trigger fixture rule")
        }
        _ = try await seed(.historical, kind: kind, client: client)
        try await Task.sleep(for: .seconds(6))
        _ = try await service.setTriggerEnabled(for: agent, id: row.id, enabled: true)
        if kind == .tool {
            _ = try await seed(.unmatched, kind: kind, client: client)
            _ = try await seed(.pending, kind: kind, client: client)
        }
        try await Task.sleep(for: .seconds(6))
        guard try await chat.conversations().allSatisfy({ conversationIDs.contains($0.id) }),
              kind.replyCount(fixture) == 0 else {
            throw RuntimeError.integrity("historical event replay")
        }

        let taskID = try await seed(.current, kind: kind, client: client)
        var resultID: Int64?
        for _ in 0..<150 {
            let fresh = try await chat.conversations().filter { !conversationIDs.contains($0.id) }
            guard fresh.count <= 1,
                  fresh.allSatisfy({ $0.agentKey == agent.key && $0.title.hasSuffix("task#\(taskID)") }) else {
                throw RuntimeError.integrity("seeded trigger conversation scope")
            }
            if let item = fresh.first {
                let page = try await chat.history(id: item.id)
                guard !page.items.contains(where: { $0.isError == true }) else {
                    throw RuntimeError.integrity("seeded trigger conversation error")
                }
                if !page.running, page.items.contains(where: {
                    $0.kind == "result" && $0.summary == CloudEgressVMFixture.reply(.openAI)
                }) { resultID = item.id; break }
            }
            try await Task.sleep(for: .milliseconds(100))
        }
        guard resultID != nil, kind.replyCount(fixture) == 1 else {
            throw RuntimeError.integrity("seeded trigger conversation completion")
        }
        _ = try await service.removeTrigger(for: agent, id: row.id)
        _ = try await service.removeTrigger(for: agent, id: sentinelRow.id)
        for previous in defaults {
            _ = try await service.setTriggerEnabled(for: agent, id: previous.id, enabled: true)
        }
        let restored = try await service.triggers(for: agent)
        guard Set(restored.map(\.id)) == ids,
              baseline.allSatisfy({ previous in restored.contains { $0.id == previous.id && $0.rule == previous.rule } }) else {
            throw RuntimeError.integrity("seeded trigger fixture cleanup")
        }
    }

    private static func seed(_ event: Event, kind: Kind, client: AuthenticatedBackendClient) async throws -> Int64 {
        let summary = event == .historical ? "Historical synthetic \(kind.rawValue)" : kind.summary
        let write: String
        if kind == .tool {
            let tool = event == .unmatched ? "fixture_other_tool" : "fixture_selected_tool"
            let useID = event == .current ? "scheduler-fixture-pending" : "scheduler-fixture-\(event.rawValue)"
            let toolUse = """
                INSERT INTO activity(exploration_id,kind,tool,tool_use_id,detail)
                SELECT exploration_id,'tool_use','\(tool)','\(useID)','Synthetic tool input'
                FROM tasks WHERE description = '\(CloudEgressVMFixture.currentTaskDescription)' AND deleted_at IS NULL;
                """
            let toolResult = """
                INSERT INTO activity(exploration_id,kind,tool,tool_use_id,detail)
                SELECT exploration_id,'tool_result','\(tool)','\(useID)','Synthetic tool output'
                FROM tasks WHERE description = '\(CloudEgressVMFixture.currentTaskDescription)' AND deleted_at IS NULL;
                """
            switch event {
            case .historical, .unmatched: write = toolUse + "\n" + toolResult
            case .pending: write = toolUse
            case .current: write = toolResult
            }
        } else {
            write = """
                INSERT INTO exploration_nodes(exploration_id,kind,payload,state)
                SELECT exploration_id,'\(kind.rawValue)',jsonb_build_object('summary','\(summary)','vulnclass','fixture','severity','low'),'\(kind.state)'
                FROM tasks WHERE description = '\(CloudEgressVMFixture.currentTaskDescription)' AND deleted_at IS NULL;
                """
        }
        let code = """
        import json, os, platform, re, subprocess, urllib.parse
        if platform.system() != 'Linux' or platform.machine() != 'aarch64' or os.getuid() != 1000:
            raise RuntimeError('Isolated guest required')
        dsn=urllib.parse.urlsplit(os.environ.get('ARTEX_PG_DSN',''))
        password=urllib.parse.unquote(dsn.password or '')
        if (dsn.scheme, dsn.hostname, dsn.port, dsn.username, dsn.path, dsn.query) != ('postgres','127.0.0.1',5432,'artex','/artex','sslmode=disable') or not re.fullmatch('[0-9a-f]{64}',password):
            raise RuntimeError('Dedicated guest database required')
        sql = '''
        BEGIN;
        SET LOCAL statement_timeout = '4s';
        DO $$ BEGIN
          IF (SELECT count(*) FROM tasks WHERE description = '\(CloudEgressVMFixture.currentTaskDescription)' AND deleted_at IS NULL) <> 1
          OR EXISTS (SELECT 1 FROM exploration_nodes WHERE kind = '\(kind.rawValue)' AND payload->>'summary' = '\(summary)')
          THEN RAISE EXCEPTION 'unexpected seeded event fixture state'; END IF;
        END $$;
        \(write)
        SELECT id FROM tasks WHERE description = '\(CloudEgressVMFixture.currentTaskDescription)' AND deleted_at IS NULL;
        COMMIT;
        '''
        env={'PATH':'/usr/libexec/postgresql16:/usr/bin:/bin','PGHOST':'127.0.0.1','PGPORT':'5432',
             'PGDATABASE':'artex','PGUSER':'artex','PGPASSWORD':password,'PGCONNECT_TIMEOUT':'2'}
        result=subprocess.run(['psql','-XqAt','--no-password','-v','ON_ERROR_STOP=1'],input=sql,text=True,env=env,
                              capture_output=True,timeout=8)
        if result.returncode != 0 or not result.stdout.strip().isdigit():
            raise RuntimeError('Synthetic event write failed')
        print(json.dumps({'task_id':int(result.stdout.strip())}))
        """
        struct Execution: Encodable { let code: String; let timeoutMs = 12_000 }
        struct Request: Encodable { let kind = "script"; let exec: Execution; let params: [String: String] = [:] }
        struct Reply: Decodable { let isError: Bool; let output: String }
        struct Proof: Decodable { let taskId: Int64 }
        let body = try BackendJSONCoding.encode(Request(exec: Execution(code: code)))
        let response = try await client.send(method: "POST", path: "/api/tools/custom/test", body: body, bearer: nil)
        guard response.status == 200 else { throw RuntimeError.integrity("seeded event fixture transport") }
        let reply = try BackendJSONCoding.decode(Reply.self, from: response.body)
        guard !reply.isError, reply.output.utf8.count <= 128 else { throw RuntimeError.integrity("seeded event fixture write") }
        let proof = try BackendJSONCoding.decode(Proof.self, from: Data(reply.output.utf8))
        guard proof.taskId > 0 else { throw RuntimeError.integrity("seeded event fixture task identity") }
        return proof.taskId
    }
}
#endif
