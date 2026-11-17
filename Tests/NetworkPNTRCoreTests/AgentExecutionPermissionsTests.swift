import XCTest
@testable import NetworkPNTRCore

final class AgentExecutionPermissionsTests: XCTestCase {
    @MainActor func testWebSearchAndShellWriteOnlyChangedFieldsAfterGateRecheck() async throws {
        let api = ChatTestTransport()
        let editor = AgentPromptEditor(key: "worker", service: AgentCatalogService(client: api))
        try api.enqueue(detail())
        await editor.refresh()
        try api.enqueue(["web_search_enabled": true])
        await editor.loadWebSearchAvailability()
        var draft = try XCTUnwrap(editor.executionDraft)
        draft.webSearch = true
        draft.interactiveShell = true
        editor.editExecution(draft)
        try api.enqueue(["web_search_enabled": true])
        try api.enqueue(["ok": true])
        try api.enqueue(detail(web: true, shell: true))
        await editor.saveExecution()

        XCTAssertEqual(api.calls.map(\.path), [
            "/api/agents/worker", "/api/settings", "/api/settings", "/api/agents/worker/config", "/api/agents/worker"
        ])
        let body = try XCTUnwrap(api.calls[3].body)
        XCTAssertEqual(try JSONSerialization.jsonObject(with: body) as? [String: Bool],
                       ["web_search": true, "interactive_shell": true])
        XCTAssertTrue(editor.executionSaved)
    }

    @MainActor func testClosingGlobalGateDiscardsOnlyWebEditBeforeWrite() async throws {
        let api = ChatTestTransport()
        let editor = AgentPromptEditor(key: "worker", service: AgentCatalogService(client: api))
        try api.enqueue(detail())
        await editor.refresh()
        try api.enqueue(["web_search_enabled": true])
        await editor.loadWebSearchAvailability()
        var draft = try XCTUnwrap(editor.executionDraft)
        draft.webSearch = true
        draft.interactiveShell = true
        editor.editExecution(draft)
        try api.enqueue(["web_search_enabled": false])
        await editor.saveExecution()

        XCTAssertEqual(api.calls.map(\.method), ["GET", "GET", "GET"])
        XCTAssertEqual(editor.webSearchEnabled, false)
        XCTAssertEqual(editor.executionDraft?.webSearch, false)
        XCTAssertEqual(editor.executionDraft?.interactiveShell, true)
        XCTAssertTrue(editor.canSaveExecution)
        XCTAssertNotNil(editor.failure)
    }

    @MainActor func testFailedGateReadAndHiddenPreferencesNeverProduceFlagWrites() async throws {
        for key in ["worker", "goals"] {
            let api = ChatTestTransport()
            let editor = AgentPromptEditor(key: key, service: AgentCatalogService(client: api))
            try api.enqueue(detail(key: key, web: true))
            await editor.refresh()
            if key == "worker" { try api.enqueue([:], status: 503) }
            await editor.loadWebSearchAvailability()
            var draft = try XCTUnwrap(editor.executionDraft)
            draft.webSearch = false
            draft.interactiveShell = key == "goals"
            editor.editExecution(draft)
            await editor.saveExecution()

            XCTAssertNil(editor.webSearchEnabled)
            XCTAssertEqual(editor.executionDraft?.webSearch, true)
            XCTAssertEqual(api.calls.map(\.method), key == "goals" ? ["GET"] : ["GET", "GET"])
        }
    }

    private func detail(key: String = "worker", web: Bool = false, shell: Bool = false) -> [String: Any] {
        ["agent": ["key": key, "web_search": web, "interactive_shell": shell], "prompt": "initial"]
    }
}
