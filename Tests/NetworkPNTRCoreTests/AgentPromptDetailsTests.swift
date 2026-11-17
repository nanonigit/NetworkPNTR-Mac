import XCTest
@testable import NetworkPNTRCore

final class AgentPromptDetailsTests: XCTestCase {
    func testOnlyRecognizedSystemVersionNotesAreLocalized() throws {
        let json = """
        [
          {"version":5,"template_text":"原文","note":"恢复为内置默认","updated_by":"system"},
          {"version":4,"template_text":"原文","note":"内置默认","updated_by":"ui"},
          {"version":3,"template_text":"原文","note":"内置默认"},
          {"version":2,"template_text":"原文","note":"自訂說明","updated_by":"system"},
          {"version":1,"template_text":"原文","note":"内置默认","updated_by":"system"}
        ]
        """
        let versions = try BackendJSONCoding.decode([AgentPromptDetails.Version].self, from: Data(json.utf8))
        XCTAssertEqual(versions.map { $0.displayNote(language: .english) }, [
            "Restored built-in default", "内置默认", "内置默认", "自訂說明", "Built-in default"
        ])
        XCTAssertEqual(versions.map { $0.displayNote(language: .japanese) }, [
            "組み込みの既定値に復元", "内置默认", "内置默认", "自訂說明", "組み込みの既定値"
        ])
        XCTAssertEqual(versions.first?.note, "恢复为内置默认")
        XCTAssertTrue(versions.allSatisfy { $0.templateText == "原文" })
    }

    @MainActor func testReadsLiteralPromptHistoryAndWrapUpFromSelectedAgent() async throws {
        let api = ChatTestTransport()
        let text = "  **原文**\n{{.target}}\n"
        try api.enqueue([
            "agent": ["key": "worker"],
            "prompt": text,
            "variables": [["name": "target", "description": "Target", "example": "literal", "source": "runtime"]],
            "versions": [
                ["version": 2, "template_text": text, "ts": "2026-11-06T00:00:00.123Z"],
                ["version": 1, "template_text": "previous", "note": "literal note"]
            ],
            "wrapup_prompt": "override",
            "wrapup_default": "default",
            "wrapup_max_turns": 0,
            "wrapup_max_turns_default": 5,
            "task_timeout_wrapup_supported": true,
            "task_timeout_wrapup_default": "task default",
            "task_timeout_wrapup_max_turns": 3
        ])
        let detail = try await AgentCatalogService(client: api).promptDetails(key: "worker")
        XCTAssertEqual(api.calls.map(\.method), ["GET"])
        XCTAssertEqual(api.calls.map(\.path), ["/api/agents/worker"])
        XCTAssertNil(api.calls.first?.body)
        XCTAssertEqual(detail.prompt, text)
        XCTAssertEqual(detail.variables.map(\.name), ["target"])
        XCTAssertEqual(detail.versions.map(\.version), [2, 1])
        XCTAssertEqual(detail.versions[0].templateText, text)
        XCTAssertNil(detail.versions[0].note)
        XCTAssertEqual(detail.versions[1].note, "literal note")
        XCTAssertEqual(detail.wrapUp.prompt, "override")
        XCTAssertEqual(detail.wrapUp.builtIn, "default")
        XCTAssertEqual(detail.wrapUp.savedRounds, 0)
        XCTAssertEqual(detail.wrapUp.effectiveRounds, 5)
        XCTAssertEqual(detail.taskTimeout?.builtIn, "task default")
        XCTAssertEqual(detail.taskTimeout?.effectiveRounds, 3)
    }

    @MainActor func testMissingOptionalValuesKeepEmptyStateAndSuppressUnsupportedSection() async throws {
        let api = ChatTestTransport()
        try api.enqueue(["agent": ["key": "custom_7"], "versions": NSNull(),
                         "task_timeout_wrapup_supported": false, "task_timeout_wrapup_default": "hidden"])
        let detail = try await AgentCatalogService(client: api).promptDetails(key: "custom_7")
        XCTAssertEqual(detail.prompt, "")
        XCTAssertTrue(detail.versions.isEmpty)
        XCTAssertTrue(detail.variables.isEmpty)
        XCTAssertNil(detail.taskTimeout)
    }

    @MainActor func testRejectsUnsafeKeysBeforeRequestAndWrongAgentAfterResponse() async throws {
        let api = ChatTestTransport()
        let service = AgentCatalogService(client: api)
        for key in ["", "1agent", "../worker", "a/b", "a?limit=1", "a%2fb", "a\n", "自作"] {
            do {
                _ = try await service.promptDetails(key: key)
                XCTFail("Expected invalid request")
            } catch BackendAPIError.invalidResponse {}
        }
        XCTAssertTrue(api.calls.isEmpty)

        try api.enqueue(["agent": ["key": "auto"], "prompt": "wrong agent"])
        do {
            _ = try await service.promptDetails(key: "worker")
            XCTFail("Expected mismatched response to fail")
        } catch BackendAPIError.invalidResponse {}
    }

    func testVariableDisplayLocalizesSeededLabelsAndPreservesCustomContent() throws {
        let row = try JSONSerialization.data(withJSONObject: [
            "key": "worker", "name": "worker", "builtin": true, "enabled": true
        ])
        let worker = try BackendJSONCoding.decode(AgentCatalogEntry.self, from: row)
        let detailData = try JSONSerialization.data(withJSONObject: [
            "agent": ["key": "worker"],
            "variables": [
                ["name": "Now", "description": "서버 현재 시각", "example": "CST", "source": "runtime"],
                ["name": "ProxyAddr", "description": "legacy seed", "example": "sample", "source": "runtime"],
                ["name": "Custom", "description": "説明 그대로", "example": "literal", "source": "other"]
            ]
        ])
        let variables = try BackendJSONCoding.decode(AgentPromptDetails.self, from: detailData).variables
        XCTAssertTrue(variables[0].displayDescription(agent: worker, language: .japanese).contains("サーバー時刻"))
        XCTAssertTrue(variables[1].displayDescription(agent: worker, language: .english).hasPrefix("Recording proxy"))
        XCTAssertEqual(variables[2].displayDescription(agent: worker, language: .japanese), "説明 그대로")
    }

    @MainActor func testServerFailureAndCancellationDoNotReturnDetails() async throws {
        let api = ChatTestTransport()
        let service = AgentCatalogService(client: api)
        try api.enqueue(["error": "private details"], status: 404)
        do {
            _ = try await service.promptDetails(key: "worker")
            XCTFail("Expected missing agent status")
        } catch BackendAPIError.status(404) {}

        api.handler = { _ in
            withUnsafeCurrentTask { $0?.cancel() }
            return try ChatTestTransport.response(["agent": ["key": "worker"]])
        }
        let task = Task { try await service.promptDetails(key: "worker") }
        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch is CancellationError {}
    }
}
