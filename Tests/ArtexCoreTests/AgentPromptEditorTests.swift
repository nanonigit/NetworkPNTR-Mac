import XCTest
@testable import ArtexCore

final class AgentPromptEditorTests: XCTestCase {
    @MainActor func testSaveSendsLiteralBodyOnceAndLoadsAcknowledgedVersion() async throws {
        let api = ChatTestTransport()
        let editor = AgentPromptEditor(key: "reporter", service: AgentCatalogService(client: api))
        try api.enqueue(detail("original", version: 1))
        await editor.refresh()

        let edited = "  Test {{.Now}}\n日本語\n"
        editor.edit(edited)
        try api.enqueue(["version": 2])
        try api.enqueue(detail(edited, version: 2))
        await editor.save()

        XCTAssertEqual(api.calls.map(\.method), ["GET", "PUT", "GET"])
        XCTAssertEqual(api.calls[1].path, "/api/agents/reporter/prompt")
        let body = try XCTUnwrap(api.calls[1].body)
        XCTAssertEqual(try JSONSerialization.jsonObject(with: body) as? [String: String],
                       ["template": edited, "note": ""])
        XCTAssertEqual(editor.savedVersion, 2)
        XCTAssertEqual(editor.details?.versions.first?.templateText, edited)
        XCTAssertFalse(editor.hasUnsavedChanges)
    }

    @MainActor func testRejectedTemplateLeavesDraftEditableWithoutReadingHistory() async throws {
        let api = ChatTestTransport()
        let editor = AgentPromptEditor(key: "reporter", service: AgentCatalogService(client: api))
        try api.enqueue(detail("original", version: 1))
        await editor.refresh()

        editor.edit("{{.Unknown}}")
        try api.enqueue(["error": "raw parser message"], status: 400)
        await editor.save()
        XCTAssertEqual(editor.draft, "{{.Unknown}}")
        XCTAssertTrue(editor.hasUnsavedChanges)
        XCTAssertTrue(editor.canSave)
        XCTAssertFalse(editor.requiresRefresh)
        XCTAssertNil(editor.savedVersion)
        XCTAssertEqual(api.calls.map(\.method), ["GET", "PUT"])
        XCTAssertFalse(editor.failure?.text(language: .english).contains("raw parser message") ?? true)
    }

    @MainActor func testUncertainWriteBlocksReplayUntilExplicitRefreshAndPreservesDraft() async throws {
        let api = ChatTestTransport()
        let editor = AgentPromptEditor(key: "reporter", service: AgentCatalogService(client: api))
        try api.enqueue(detail("original", version: 1))
        await editor.refresh()

        editor.edit("new draft")
        api.handler = { _ in throw URLError(.networkConnectionLost) }
        await editor.save()
        await editor.save()
        XCTAssertEqual(api.calls.map(\.method), ["GET", "PUT"])
        XCTAssertTrue(editor.requiresRefresh)
        XCTAssertNil(editor.savedVersion)

        api.handler = nil
        try api.enqueue(detail("different current", version: 2))
        await editor.refresh()
        XCTAssertEqual(editor.draft, "new draft")
        XCTAssertEqual(editor.details?.prompt, "different current")
        XCTAssertTrue(editor.canSave)
    }

    @MainActor func testAcknowledgementSurvivesStaleReadAndRefreshDoesNotReplaySave() async throws {
        let api = ChatTestTransport()
        let editor = AgentPromptEditor(key: "reporter", service: AgentCatalogService(client: api))
        try api.enqueue(detail("original", version: 1))
        await editor.refresh()

        editor.edit("saved")
        try api.enqueue(["version": 2])
        try api.enqueue(detail("original", version: 1))
        await editor.save()
        XCTAssertEqual(editor.savedVersion, 2)
        XCTAssertTrue(editor.requiresRefresh)
        XCTAssertFalse(editor.canSave)

        try api.enqueue(detail("saved", version: 2))
        await editor.refresh()
        XCTAssertEqual(api.calls.map(\.method), ["GET", "PUT", "GET", "GET"])
        XCTAssertEqual(editor.savedVersion, 2)
        XCTAssertFalse(editor.hasUnsavedChanges)
    }

    @MainActor func testSaveAndRefreshCannotDispatchWhileFirstWriteIsInFlight() async throws {
        let api = ChatTestTransport()
        let editor = AgentPromptEditor(key: "reporter", service: AgentCatalogService(client: api))
        try api.enqueue(detail("original", version: 1))
        await editor.refresh()
        editor.edit("first draft")
        var held: CheckedContinuation<BackendHTTPResponse, any Error>?
        api.handler = { _ in try await withCheckedThrowingContinuation { held = $0 } }
        let firstSave = Task { await editor.save() }
        for _ in 0..<2_000 {
            if held != nil { break }
            await Task.yield()
        }
        guard let held else {
            firstSave.cancel()
            XCTFail("Write did not reach transport")
            return
        }
        await editor.save()
        await editor.refresh()
        editor.edit("must not replace the submitted draft")
        XCTAssertEqual(api.calls.map(\.method), ["GET", "PUT"])
        XCTAssertEqual(editor.draft, "first draft")

        api.handler = nil
        try api.enqueue(detail("first draft", version: 2))
        held.resume(returning: try ChatTestTransport.response(["version": 2]))
        await firstSave.value
        XCTAssertEqual(api.calls.map(\.method), ["GET", "PUT", "GET"])
        XCTAssertEqual(editor.savedVersion, 2)
    }

    private func detail(_ text: String, version: Int) -> [String: Any] {
        [
            "agent": ["key": "reporter"],
            "prompt": text,
            "versions": [["version": version, "template_text": text]]
        ]
    }
}
