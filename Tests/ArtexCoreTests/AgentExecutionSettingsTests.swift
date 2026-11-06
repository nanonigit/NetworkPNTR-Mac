import XCTest
@testable import ArtexCore

final class AgentExecutionSettingsTests: XCTestCase {
    @MainActor func testUnbindIsExplicitNullAndOnlyChangedLimitsAreWritten() async throws {
        let api = ChatTestTransport()
        let editor = AgentPromptEditor(key: "worker", service: AgentCatalogService(client: api))
        try api.enqueue(detail(key: "worker", profile: 7))
        await editor.refresh()
        let draft = try XCTUnwrap(editor.executionDraft)
        XCTAssertEqual(draft.profileID, 7)
        editor.editExecution(.init(profileID: nil, maxTurns: "12", runSeconds: draft.runSeconds))
        try api.enqueue(["ok": true])
        try api.enqueue(detail(key: "worker", profile: nil, turns: 12))
        await editor.saveExecution()
        XCTAssertEqual(api.calls.map(\.method), ["GET", "PUT", "GET"])
        XCTAssertEqual(api.calls[1].path, "/api/agents/worker/config")
        let body = try XCTUnwrap(api.calls[1].body)
        let fields = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(Set(fields.keys), ["llm_profile_id", "max_turns"])
        XCTAssertTrue(fields["llm_profile_id"] is NSNull)
        XCTAssertEqual(fields["max_turns"] as? Int, 12)
        XCTAssertTrue(editor.executionSaved)
    }

    @MainActor func testGoalsOmitsLimitsAndRejectsMissingModel() async throws {
        let api = ChatTestTransport()
        let editor = AgentPromptEditor(key: "goals", service: AgentCatalogService(client: api))
        try api.enqueue(detail(key: "goals", profile: nil))
        await editor.refresh()
        editor.editExecution(.init(profileID: 99, maxTurns: "0", runSeconds: "0"))
        await editor.saveExecution()
        XCTAssertEqual(api.calls.count, 1)
        editor.editExecution(.init(profileID: 7, maxTurns: "0", runSeconds: "0"))
        try api.enqueue(["ok": true])
        try api.enqueue(detail(key: "goals", profile: 7))
        await editor.saveExecution()
        let body = try XCTUnwrap(api.calls[1].body)
        XCTAssertEqual(try JSONSerialization.jsonObject(with: body) as? [String: Int], ["llm_profile_id": 7])
        XCTAssertTrue(editor.executionSaved)
    }

    @MainActor func testUnexpectedReadbackKeepsExecutionAndPromptDrafts() async throws {
        let api = ChatTestTransport()
        let editor = AgentPromptEditor(key: "worker", service: AgentCatalogService(client: api))
        try api.enqueue(detail(key: "worker", profile: nil))
        await editor.refresh()
        editor.edit("unrelated prompt draft")
        editor.editExecution(.init(profileID: nil, maxTurns: "12", runSeconds: "45"))
        try api.enqueue(["ok": true])
        try api.enqueue(detail(key: "worker", profile: 7, turns: 12))
        await editor.saveExecution()
        XCTAssertFalse(editor.executionSaved)
        XCTAssertNotNil(editor.failure)
        XCTAssertEqual(editor.executionDraft?.runSeconds, "45")
        XCTAssertEqual(editor.executionDraft?.profileID, 7)
        XCTAssertEqual(editor.draft, "unrelated prompt draft")
    }

    private func detail(key: String, profile: Int?, turns: Int = 5) -> [String: Any] {
        let agent: [String: Any] = ["key": key, "llm_profile_id": profile.map { $0 as Any } ?? NSNull(),
                                    "max_turns": turns, "run_seconds": 600]
        return ["agent": agent, "prompt": "initial",
                "llm_profiles": [["id": 7, "name": "Fixture", "model": "fixture", "is_default": false]]]
    }
}
