import XCTest
@testable import NetworkPNTRCore

final class AgentWrapUpEditorTests: XCTestCase {
    @MainActor func testSavePreservesLiteralPromptAndOtherDraft() async throws {
        let api = ChatTestTransport()
        let editor = AgentPromptEditor(key: "worker", service: AgentCatalogService(client: api))
        try api.enqueue(detail())
        await editor.refresh()
        editor.edit("main draft")
        let literal = "  custom 日本語\n"
        editor.editWrapUp(.normal, draft: .init(prompt: literal, rounds: "4"))
        editor.editWrapUp(.taskTimeout, draft: .init(prompt: "timeout draft", rounds: "6"))
        try api.enqueue(["ok": true])
        try api.enqueue(detail(normal: literal, rounds: 4))
        await editor.saveWrapUp(.normal)

        XCTAssertEqual(api.calls.map(\.method), ["GET", "PUT", "GET"])
        XCTAssertEqual(api.calls[1].path, "/api/agents/worker/wrapup")
        let payload = try XCTUnwrap(api.calls[1].body)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: payload) as? [String: Any])
        XCTAssertEqual(object["prompt"] as? String, literal)
        XCTAssertEqual(object["max_turns"] as? Int, 4)
        XCTAssertTrue(editor.wrapUpSaved)
        XCTAssertEqual(editor.draft, "main draft")
        XCTAssertEqual(editor.wrapUpDraft(.taskTimeout)?.prompt, "timeout draft")
        XCTAssertFalse(editor.canSaveWrapUp(.normal))
    }

    @MainActor func testTimeoutResetReadsDefaultsAndKeepsNormalDraft() async throws {
        let api = ChatTestTransport()
        let editor = AgentPromptEditor(key: "worker", service: AgentCatalogService(client: api))
        try api.enqueue(detail(timeout: "custom", timeoutRounds: 3))
        await editor.refresh()
        editor.editWrapUp(.normal, draft: .init(prompt: "keep", rounds: "4"))
        try api.enqueue(["ok": true])
        try api.enqueue(detail())
        await editor.restoreWrapUp(.taskTimeout)
        XCTAssertEqual(api.calls.map(\.method), ["GET", "POST", "GET"])
        XCTAssertEqual(api.calls[1].path, "/api/agents/worker/wrapup/task-timeout/reset")
        XCTAssertEqual(editor.wrapUpDraft(.taskTimeout)?.rounds, "0")
        XCTAssertEqual(editor.details?.taskTimeout?.effectiveRounds, 10)
        XCTAssertEqual(editor.wrapUpDraft(.normal)?.prompt, "keep")
    }

    @MainActor func testFailedWriteRequiresReloadAndPreservesDraftAfterPartialPersistence() async throws {
        let api = ChatTestTransport()
        let editor = AgentPromptEditor(key: "worker", service: AgentCatalogService(client: api))
        try api.enqueue(detail())
        await editor.refresh()
        editor.editWrapUp(.normal, draft: .init(prompt: "partial", rounds: "7"))
        try api.enqueue(["error": "partial write"], status: 500)
        await editor.saveWrapUp(.normal)
        XCTAssertTrue(editor.requiresRefresh)
        XCTAssertFalse(editor.canSaveWrapUp(.normal))
        try api.enqueue(detail(normal: "partial"))
        await editor.refresh()
        XCTAssertEqual(api.calls.map(\.method), ["GET", "PUT", "GET"])
        XCTAssertEqual(editor.wrapUpDraft(.normal)?.rounds, "7")
        XCTAssertTrue(editor.canSaveWrapUp(.normal))
        XCTAssertFalse(editor.wrapUpSaved)
    }

    private func detail(normal: String = "", rounds: Int = 0, timeout: String = "", timeoutRounds: Int = 0) -> [String: Any] {
        ["agent": ["key": "worker"], "prompt": "main", "wrapup_prompt": normal, "wrapup_max_turns": rounds,
         "task_timeout_wrapup_supported": true, "task_timeout_wrapup_prompt": timeout,
         "task_timeout_wrapup_max_turns": timeoutRounds, "task_timeout_wrapup_max_turns_default": 10]
    }
}
