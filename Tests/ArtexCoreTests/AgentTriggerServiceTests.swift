import Foundation
import XCTest
@testable import ArtexCore

final class AgentTriggerServiceTests: XCTestCase {
    private let id: Int64 = 9_007_199_254_740_993

    private func agent(_ builtin: Bool = false) throws -> AgentCatalogEntry {
        try BackendJSONCoding.decode(AgentCatalogEntry.self, from: JSONSerialization.data(withJSONObject: [
            "key": "reporter", "name": "Fixture", "builtin": builtin, "enabled": true
        ]))
    }

    private func row(_ rule: AgentTriggerRule, owner: String = "reporter") throws -> [String: Any] {
        var row = try XCTUnwrap(JSONSerialization.jsonObject(with: BackendJSONCoding.encode(rule)) as? [String: Any])
        row["id"] = id
        row["agent_key"] = owner
        return row
    }

    private var rule: AgentTriggerRule {
        var rule = AgentTriggerRule()
        rule.enabled = false
        rule.intervalSec = 60
        rule.onFinding = true
        rule.onGoalMet = true
        rule.onTaskTimeout = true
        rule.onToolCall = true
        rule.onTaskCreate = true
        rule.intervalMessage = "Interval"
        rule.findingMessage = "Finding"
        rule.goalMessage = "Goal"
        rule.taskTimeoutMessage = "Timeout"
        rule.toolCallMessage = "Tool call"
        rule.taskCreateMessage = "Task creation"
        rule.toolNames = ["record_fact"]
        return rule
    }

    @MainActor func testCreateAndUpdateVerifyFullRuleWithoutLosingExactID() async throws {
        let api = ChatTestTransport()
        let service = AgentCatalogService(client: api)
        let agent = try agent()
        let row = try row(rule)
        try api.enqueue(row)
        try api.enqueue(["triggers": [row]])
        let created = try await service.createTrigger(for: agent, rule: rule)
        XCTAssertEqual(created.first?.id, id)
        XCTAssertEqual(created.first?.rule, rule)
        try api.enqueue(["triggers": [row]])
        try api.enqueue(["ok": true])
        var next = rule
        next.onFinding = false
        try api.enqueue(["triggers": [try self.row(next)]])
        let changed = try await service.updateTrigger(for: agent, id: id, rule: next)
        XCTAssertEqual(changed.first?.rule, next)
        XCTAssertEqual(api.calls.map(\.method), ["POST", "GET", "GET", "PATCH", "GET"])
        XCTAssertEqual(api.calls[3].path, "/api/triggers/9007199254740993")
        let body = try XCTUnwrap(api.calls[0].body)
        XCTAssertEqual(try BackendJSONCoding.decode(AgentTriggerRule.self, from: body), rule)
        XCTAssertFalse(String(decoding: body, as: UTF8.self).contains("agent_key"))
    }

    @MainActor func testWrongOwnerAndUnconfirmedDeleteDoNotReplay() async throws {
        let api = ChatTestTransport()
        let service = AgentCatalogService(client: api)
        let agent = try agent()
        try api.enqueue(["triggers": [try row(rule, owner: "other")]])
        do {
            _ = try await service.removeTrigger(for: agent, id: id)
            XCTFail("Wrong owner accepted")
        } catch { XCTAssertEqual(api.calls.map(\.method), ["GET"]) }
        try api.enqueue(["triggers": [try row(rule)]])
        try api.enqueue(["deleted": id])
        try api.enqueue(["triggers": [try row(rule)]])
        do {
            _ = try await service.removeTrigger(for: agent, id: id)
            XCTFail("Unconfirmed removal accepted")
        } catch { XCTAssertEqual(api.calls.map(\.method), ["GET", "GET", "DELETE", "GET"]) }
    }

    @MainActor func testInvalidDraftAndBuiltinDoNotDispatch() async throws {
        let api = ChatTestTransport()
        let service = AgentCatalogService(client: api)
        var invalid = AgentTriggerRule()
        invalid.onToolCall = true
        do {
            _ = try await service.createTrigger(for: agent(), rule: invalid)
            XCTFail("Missing tool filter accepted")
        } catch {}
        do {
            _ = try await service.createTrigger(for: agent(true), rule: rule)
            XCTFail("Built-in agent accepted")
        } catch {}
        XCTAssertTrue(api.calls.isEmpty)
    }

    @MainActor func testPolicyOnlySendsItsThreeFieldsAndReadsBack() async throws {
        let api = ChatTestTransport()
        let service = AgentCatalogService(client: api)
        try api.enqueue(["agent": ["key": "reporter", "builtin": false, "trigger_run_mode": "serial",
                                  "trigger_merge_mode": "all", "trigger_max_parallel": 5]])
        try api.enqueue(["ok": true])
        try api.enqueue(["agent": ["key": "reporter", "builtin": false, "trigger_run_mode": "parallel",
                                  "trigger_merge_mode": "by_task", "trigger_max_parallel": 0]])
        let policy = AgentTriggerPolicy(runMode: .parallel, mergeMode: .byTask, maxParallel: 0)
        let stored = try await service.saveTriggerPolicy(for: agent(), policy: policy)
        XCTAssertEqual(stored, policy)
        XCTAssertEqual(api.calls.map(\.path), ["/api/agents/reporter", "/api/agents/reporter/config", "/api/agents/reporter"])
        let sent = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(api.calls[1].body)) as? [String: Any])
        XCTAssertEqual(Set(sent.keys), ["trigger_run_mode", "trigger_merge_mode", "trigger_max_parallel"])
    }
}
