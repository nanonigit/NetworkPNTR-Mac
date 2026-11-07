#if DEBUG
import ArtexCore
import Foundation

@MainActor enum FindingTriggerProbe {
    private enum Event: String { case historical, current }

    static func verify(client: AuthenticatedBackendClient, chat: ChatService, fixture: CloudEgressVMFixture) async throws {
        let service = AgentCatalogService(client: client)
        guard let agent = try await service.list().first(where: { $0.key == "reporter" && !$0.builtin }) else {
            throw RuntimeError.integrity("finding trigger fixture owner")
        }
        let baseline = try await service.triggers(for: agent)
        let ids = Set(baseline.map(\.id))
        let conversationIDs = Set(try await chat.conversations().map(\.id))
        let defaults = baseline.filter { $0.rule.enabled && $0.rule.onFinding }
        for row in defaults {
            _ = try await service.setTriggerEnabled(for: agent, id: row.id, enabled: false)
        }
        // Keep one enabled non-finding rule so the pinned scheduler advances event watermarks.
        var sentinel = AgentTriggerRule()
        sentinel.onToolCall = true
        sentinel.toolNames = ["nonexistent_fixture_tool"]
        let armed = try await service.createTrigger(for: agent, rule: sentinel)
        guard let sentinelRow = armed.first(where: { !ids.contains($0.id) }) else {
            throw RuntimeError.integrity("finding trigger sentinel")
        }

        var rule = AgentTriggerRule()
        rule.enabled = false
        rule.onFinding = true
        rule.findingMessage = CloudEgressVMFixture.findingPrompt
        let rows = try await service.createTrigger(for: agent, rule: rule)
        guard let row = rows.first(where: { !ids.contains($0.id) && $0.id != sentinelRow.id }) else {
            throw RuntimeError.integrity("finding trigger fixture rule")
        }
        _ = try await seed(.historical, client: client)
        try await Task.sleep(for: .seconds(6))
        _ = try await service.setTriggerEnabled(for: agent, id: row.id, enabled: true)
        try await Task.sleep(for: .seconds(6))
        guard try await chat.conversations().allSatisfy({ conversationIDs.contains($0.id) }),
              fixture.snapshot.findingReplies == 0 else {
            throw RuntimeError.integrity("historical finding replay")
        }

        let taskID = try await seed(.current, client: client)
        var resultID: Int64?
        for _ in 0..<150 {
            let fresh = try await chat.conversations().filter { !conversationIDs.contains($0.id) }
            guard fresh.count <= 1,
                  fresh.allSatisfy({ $0.agentKey == agent.key && $0.title.hasSuffix("task#\(taskID)") }) else {
                throw RuntimeError.integrity("finding conversation scope")
            }
            if let item = fresh.first {
                let page = try await chat.history(id: item.id)
                guard !page.items.contains(where: { $0.isError == true }) else {
                    throw RuntimeError.integrity("finding conversation error")
                }
                if !page.running, page.items.contains(where: {
                    $0.kind == "result" && $0.summary == CloudEgressVMFixture.reply(.openAI)
                }) { resultID = item.id; break }
            }
            try await Task.sleep(for: .milliseconds(100))
        }
        guard resultID != nil, fixture.snapshot.findingReplies == 1 else {
            throw RuntimeError.integrity("finding conversation completion")
        }
        _ = try await service.removeTrigger(for: agent, id: row.id)
        _ = try await service.removeTrigger(for: agent, id: sentinelRow.id)
        for previous in defaults {
            _ = try await service.setTriggerEnabled(for: agent, id: previous.id, enabled: true)
        }
        let restored = try await service.triggers(for: agent)
        guard Set(restored.map(\.id)) == ids,
              baseline.allSatisfy({ previous in restored.contains { $0.id == previous.id && $0.rule == previous.rule } }) else {
            throw RuntimeError.integrity("finding trigger fixture cleanup")
        }
    }

    private static func seed(_ event: Event, client: AuthenticatedBackendClient) async throws -> Int64 {
        let summary = event == .historical ? "Historical synthetic finding" : CloudEgressVMFixture.currentFindingSummary
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
          OR EXISTS (SELECT 1 FROM exploration_nodes WHERE kind = 'finding' AND payload->>'summary' = '\(summary)')
          THEN RAISE EXCEPTION 'unexpected finding fixture state'; END IF;
        END $$;
        INSERT INTO exploration_nodes(exploration_id,kind,payload,state)
          SELECT exploration_id,'finding',jsonb_build_object('summary','\(summary)','vulnclass','fixture','severity','low'),'confirmed'
          FROM tasks WHERE description = '\(CloudEgressVMFixture.currentTaskDescription)' AND deleted_at IS NULL;
        SELECT id FROM tasks WHERE description = '\(CloudEgressVMFixture.currentTaskDescription)' AND deleted_at IS NULL;
        COMMIT;
        '''
        env={'PATH':'/usr/libexec/postgresql16:/usr/bin:/bin','PGHOST':'127.0.0.1','PGPORT':'5432',
             'PGDATABASE':'artex','PGUSER':'artex','PGPASSWORD':password,'PGCONNECT_TIMEOUT':'2'}
        result=subprocess.run(['psql','-XqAt','--no-password','-v','ON_ERROR_STOP=1'],input=sql,text=True,env=env,
                              capture_output=True,timeout=8)
        if result.returncode != 0 or not result.stdout.strip().isdigit():
            raise RuntimeError('Synthetic finding write failed')
        print(json.dumps({'task_id':int(result.stdout.strip())}))
        """
        struct Execution: Encodable { let code: String; let timeoutMs = 12_000 }
        struct Request: Encodable { let kind = "script"; let exec: Execution; let params: [String: String] = [:] }
        struct Reply: Decodable { let isError: Bool; let output: String }
        struct Proof: Decodable { let taskId: Int64 }
        let body = try BackendJSONCoding.encode(Request(exec: Execution(code: code)))
        let response = try await client.send(method: "POST", path: "/api/tools/custom/test", body: body, bearer: nil)
        guard response.status == 200 else { throw RuntimeError.integrity("finding fixture transport") }
        let reply = try BackendJSONCoding.decode(Reply.self, from: response.body)
        guard !reply.isError, reply.output.utf8.count <= 128 else { throw RuntimeError.integrity("finding fixture write") }
        let proof = try BackendJSONCoding.decode(Proof.self, from: Data(reply.output.utf8))
        guard proof.taskId > 0 else { throw RuntimeError.integrity("finding fixture task identity") }
        return proof.taskId
    }
}
#endif
