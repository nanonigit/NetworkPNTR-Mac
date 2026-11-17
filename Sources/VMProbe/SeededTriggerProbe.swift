#if DEBUG
import NetworkPNTRCore
import Foundation

@MainActor enum SeededTriggerProbe {
    enum Kind: String {
        case finding, goal, tool, timeout

        var state: String { self == .finding ? "confirmed" : "met" }
        var prompt: String {
            switch self {
            case .finding: CloudEgressVMFixture.findingPrompt
            case .goal: CloudEgressVMFixture.goalPrompt
            case .tool: CloudEgressVMFixture.toolPrompt
            case .timeout: CloudEgressVMFixture.timeoutPrompt
            }
        }

        func matches(_ rule: AgentTriggerRule) -> Bool {
            switch self {
            case .finding: rule.onFinding
            case .goal: rule.onGoalMet
            case .tool: rule.onToolCall
            case .timeout: rule.onTaskTimeout
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
            case .timeout: fixture.snapshot.timeoutReplies
            }
        }
    }
    private enum Event: String { case historical, unmatched, pending, current }

    static func verify(
        _ kind: Kind, client: AuthenticatedBackendClient, chat: ChatService,
        fixture: CloudEgressVMFixture, repairedTimeouts: Bool = false, elapsedTimeoutProfile: Int64? = nil
    ) async throws {
        let service = AgentCatalogService(client: client)
        let agents = try await service.list()
        guard let agent = agents.first(where: { $0.key == "reporter" && !$0.builtin }) else {
            throw RuntimeError.integrity("seeded trigger fixture owner")
        }
        let baseline = try await service.triggers(for: agent)
        let ids = Set(baseline.map(\.id))
        let conversationIDs = Set(try await chat.conversations().map(\.id))
        var defaults = baseline.filter { $0.rule.enabled && (repairedTimeouts || kind.matches($0.rule)) }
            .map { (owner: agent, trigger: $0) }
        if repairedTimeouts {
            for owner in agents where !owner.builtin && owner.key != agent.key {
                let enabled = try await service.triggers(for: owner).filter { $0.rule.enabled }
                defaults.append(contentsOf: enabled.map { (owner: owner, trigger: $0) })
            }
        }
        for (owner, trigger) in defaults {
            _ = try await service.setTriggerEnabled(for: owner, id: trigger.id, enabled: false)
        }
        var sentinelID: Int64?
        if !repairedTimeouts {
            // Keep one enabled unrelated rule so the pinned scheduler advances event state.
            var sentinel = AgentTriggerRule()
            sentinel.onToolCall = true
            sentinel.toolNames = ["nonexistent_fixture_tool"]
            let armed = try await service.createTrigger(for: agent, rule: sentinel)
            guard let row = armed.first(where: { !ids.contains($0.id) }) else {
                throw RuntimeError.integrity("seeded trigger sentinel")
            }
            sentinelID = row.id
        }

        var rule = AgentTriggerRule()
        rule.enabled = false
        switch kind {
        case .finding: rule.onFinding = true; rule.findingMessage = kind.prompt
        case .goal: rule.onGoalMet = true; rule.goalMessage = kind.prompt
        case .timeout: rule.onTaskTimeout = true; rule.taskTimeoutMessage = kind.prompt
        case .tool:
            rule.onToolCall = true
            rule.toolCallMessage = kind.prompt
            rule.toolNames = ["fixture_selected_tool"]
        }
        let rows = try await service.createTrigger(for: agent, rule: rule)
        guard let row = rows.first(where: { !ids.contains($0.id) && $0.id != sentinelID }) else {
            throw RuntimeError.integrity("seeded trigger fixture rule")
        }
        let historicalTaskID = try await seed(.historical, kind: kind, client: client, requireNoEnabledRules: repairedTimeouts)
        if repairedTimeouts {
            try await waitForDisabledTimeoutClaim(taskID: historicalTaskID, client: client)
            guard try await chat.conversations().allSatisfy({ conversationIDs.contains($0.id) }),
                  kind.replyCount(fixture) == 0 else {
                throw RuntimeError.integrity("timeout fired with all rules disabled")
            }
        } else {
            try await Task.sleep(for: .seconds(6))
        }
        _ = try await service.setTriggerEnabled(for: agent, id: row.id, enabled: true)
        if kind == .tool {
            _ = try await seed(.unmatched, kind: kind, client: client)
            _ = try await seed(.pending, kind: kind, client: client)
        }
        var lateTimeoutID: Int64?
        if kind == .timeout {
            let olderTaskID = try await seed(.unmatched, kind: kind, client: client)
            guard olderTaskID < historicalTaskID else { throw RuntimeError.integrity("timeout fixture ordering") }
            lateTimeoutID = olderTaskID
        }
        let taskID: Int64
        if repairedTimeouts, let lateTimeoutID {
            taskID = lateTimeoutID
        } else {
            try await Task.sleep(for: .seconds(6))
            guard try await chat.conversations().allSatisfy({ conversationIDs.contains($0.id) }),
                  kind.replyCount(fixture) == 0 else {
                throw RuntimeError.integrity("historical event replay")
            }
            taskID = try await seed(.current, kind: kind, client: client)
        }
        let resultID = try await completedConversation(taskID: taskID, agent: agent.key, existing: conversationIDs, chat: chat)
        guard kind.replyCount(fixture) == 1 else {
            throw RuntimeError.integrity("seeded trigger conversation completion")
        }
        if repairedTimeouts {
            try await Task.sleep(for: .seconds(6))
            let fresh = try await chat.conversations().filter { !conversationIDs.contains($0.id) }
            guard fresh.map(\.id) == [resultID], kind.replyCount(fixture) == 1 else {
                throw RuntimeError.integrity("timeout event replay")
            }
        }
        if let elapsedTimeoutProfile {
            try await verifyElapsedTimeout(
                profile: elapsedTimeoutProfile, agent: agent.key, existing: conversationIDs.union([resultID]),
                client: client, chat: chat, fixture: fixture
            )
        }
        _ = try await service.removeTrigger(for: agent, id: row.id)
        if let sentinelID { _ = try await service.removeTrigger(for: agent, id: sentinelID) }
        for (owner, previous) in defaults {
            let rows = try await service.setTriggerEnabled(for: owner, id: previous.id, enabled: true)
            guard rows.contains(where: { $0.id == previous.id && $0.rule == previous.rule }) else {
                throw RuntimeError.integrity("seeded trigger default restoration")
            }
        }
        let restored = try await service.triggers(for: agent)
        guard Set(restored.map(\.id)) == ids,
              baseline.allSatisfy({ previous in restored.contains { $0.id == previous.id && $0.rule == previous.rule } }) else {
            throw RuntimeError.integrity("seeded trigger fixture cleanup")
        }
    }

    private static func completedConversation(
        taskID: Int64, agent: String, existing: Set<Int64>, chat: ChatService
    ) async throws -> Int64 {
        for _ in 0..<150 {
            let fresh = try await chat.conversations().filter { !existing.contains($0.id) }
            guard fresh.count <= 1,
                  fresh.allSatisfy({ $0.agentKey == agent && $0.title.hasSuffix("task#\(taskID)") }) else {
                throw RuntimeError.integrity("seeded trigger conversation scope")
            }
            if let item = fresh.first {
                let page = try await chat.history(id: item.id)
                guard !page.items.contains(where: { $0.isError == true }) else {
                    throw RuntimeError.integrity("seeded trigger conversation error")
                }
                if !page.running, page.items.contains(where: {
                    $0.kind == "result" && $0.summary == CloudEgressVMFixture.reply(.openAI)
                }) { return item.id }
            }
            try await Task.sleep(for: .milliseconds(100))
        }
        throw RuntimeError.timeout("seeded trigger conversation completion")
    }

    private static func verifyElapsedTimeout(
        profile: Int64, agent: String, existing: Set<Int64>, client: AuthenticatedBackendClient,
        chat: ChatService, fixture: CloudEgressVMFixture
    ) async throws {
        let service = TaskService(client: client)
        let timeoutSeconds: Int64 = 8
        var draft = TaskCreateDraft()
        draft.description = CloudEgressVMFixture.elapsedTimeoutTaskDescription
        draft.goal = "Keep this synthetic goal unmet until the task deadline."
        draft.llmProfileIds = [profile]
        draft.timeoutSeconds = timeoutSeconds
        let clock = ContinuousClock()
        let started = clock.now
        let created = try await service.create(draft)
        guard created.status != "timeout", let taskID = Int64(created.id) else {
            throw RuntimeError.integrity("elapsed timeout initial task")
        }
        var observedAt: ContinuousClock.Instant?
        for _ in 0..<150 {
            let task = try await service.detail(id: created.id)
            if task.status == "timeout" {
                observedAt = clock.now
                break
            }
            guard task.status != "done", task.status != "failed" else {
                throw RuntimeError.integrity("elapsed timeout terminal status")
            }
            try await Task.sleep(for: .milliseconds(250))
        }
        guard let observedAt, started.duration(to: observedAt) >= .seconds(timeoutSeconds - 1) else {
            throw RuntimeError.integrity("elapsed timeout observation")
        }
        // The engine compares the deadline at Unix-second precision.
        let stampedTaskID = try await scalar("""
        SELECT id FROM tasks
        WHERE id = \(taskID) AND status = 'timeout' AND timeout_seconds = \(timeoutSeconds)
          AND deadline_at = first_run_at + make_interval(secs => \(timeoutSeconds))
          AND completed_at >= deadline_at - interval '1 second';
        """, client: client)
        guard stampedTaskID == taskID else {
            throw RuntimeError.integrity("elapsed timeout deadline")
        }
        _ = try await completedConversation(taskID: taskID, agent: agent, existing: existing, chat: chat)
        guard fixture.snapshot.timeoutReplies == 2 else { throw RuntimeError.integrity("elapsed timeout reply") }
    }

    private static func waitForDisabledTimeoutClaim(taskID: Int64, client: AuthenticatedBackendClient) async throws {
        for _ in 0..<40 {
            let state = try await scalar("""
            SELECT CASE
              WHEN EXISTS (SELECT 1 FROM agent_triggers WHERE enabled) THEN 3
              WHEN EXISTS (SELECT 1 FROM scheduler_consumed_task_timeouts WHERE task_id = \(taskID)) THEN 2
              ELSE 1
            END;
            """, client: client)
            guard state != 3 else { throw RuntimeError.integrity("timeout fixture has an enabled rule") }
            if state == 2 { return }
            try await Task.sleep(for: .milliseconds(250))
        }
        throw RuntimeError.timeout("timeout claim with all rules disabled")
    }

    private static func seed(
        _ event: Event, kind: Kind, client: AuthenticatedBackendClient, requireNoEnabledRules: Bool = false
    ) async throws -> Int64 {
        let summary = event == .historical ? "Historical synthetic \(kind.rawValue)" : kind.summary
        let description: String
        switch (kind, event) {
        case (.timeout, .current): description = CloudEgressVMFixture.timeoutTaskDescription
        case (.timeout, .unmatched): description = CloudEgressVMFixture.olderTimeoutTaskDescription
        default: description = CloudEgressVMFixture.currentTaskDescription
        }
        let write: String
        let readTaskID = kind == .timeout ? "" : """
            SELECT id FROM tasks WHERE description = '\(description)' AND deleted_at IS NULL;
            """
        if kind == .timeout {
            write = """
                UPDATE tasks SET status = 'timeout', completed_at = now()
                WHERE description = '\(description)' AND deleted_at IS NULL
                  AND status IS DISTINCT FROM 'timeout'
                RETURNING id;
                """
        } else if kind == .tool {
            let tool = event == .unmatched ? "fixture_other_tool" : "fixture_selected_tool"
            let useID = event == .current ? "scheduler-fixture-pending" : "scheduler-fixture-\(event.rawValue)"
            let toolUse = """
                INSERT INTO activity(exploration_id,kind,tool,tool_use_id,detail)
                SELECT exploration_id,'tool_use','\(tool)','\(useID)','Synthetic tool input'
                FROM tasks WHERE description = '\(description)' AND deleted_at IS NULL;
                """
            let toolResult = """
                INSERT INTO activity(exploration_id,kind,tool,tool_use_id,detail)
                SELECT exploration_id,'tool_result','\(tool)','\(useID)','Synthetic tool output'
                FROM tasks WHERE description = '\(description)' AND deleted_at IS NULL;
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
                FROM tasks WHERE description = '\(description)' AND deleted_at IS NULL;
                """
        }
        let ruleGuard = requireNoEnabledRules ? """
          OR EXISTS (SELECT 1 FROM agent_triggers WHERE enabled)
          OR EXISTS (
              SELECT 1 FROM scheduler_consumed_task_timeouts AS consumed
              JOIN tasks ON tasks.id = consumed.task_id
              WHERE tasks.description = '\(description)' AND tasks.deleted_at IS NULL
          )
        """ : ""
        return try await scalar("""
        DO $$ BEGIN
          IF (SELECT count(*) FROM tasks WHERE description = '\(description)' AND deleted_at IS NULL) <> 1
          OR EXISTS (SELECT 1 FROM exploration_nodes WHERE kind = '\(kind.rawValue)' AND payload->>'summary' = '\(summary)')
          \(ruleGuard)
          THEN RAISE EXCEPTION 'unexpected seeded event fixture state'; END IF;
        END $$;
        \(write)
        \(readTaskID)
        """, client: client)
    }

    static func markHistoricalTimeoutDeleted(client: AuthenticatedBackendClient) async throws {
        _ = try await scalar("""
        UPDATE tasks SET deleted_at = now()
        WHERE status = 'timeout' AND deleted_at IS NULL
          AND description = '\(CloudEgressVMFixture.timeoutTaskDescription)'
        RETURNING id;
        """, client: client)
    }

    static func verifyMigratedTimeouts(client: AuthenticatedBackendClient) async throws {
        let count = try await scalar("""
        SELECT count(DISTINCT tasks.description)
        FROM tasks JOIN scheduler_consumed_task_timeouts AS consumed ON consumed.task_id = tasks.id
        WHERE tasks.status = 'timeout' AND tasks.description IN (
            '\(CloudEgressVMFixture.olderTimeoutTaskDescription)',
            '\(CloudEgressVMFixture.currentTaskDescription)',
            '\(CloudEgressVMFixture.timeoutTaskDescription)'
        )
          AND (tasks.description <> '\(CloudEgressVMFixture.timeoutTaskDescription)' OR tasks.deleted_at IS NOT NULL)
          AND EXISTS (
              SELECT 1 FROM scheduler_state WHERE key = 'task_timeout_membership_v1' AND value = '1'
          );
        """, client: client)
        guard count == 3 else { throw RuntimeError.integrity("timeout upgrade migration") }
    }

    private static func scalar(_ sql: String, client: AuthenticatedBackendClient) async throws -> Int64 {
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
        \(sql)
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
