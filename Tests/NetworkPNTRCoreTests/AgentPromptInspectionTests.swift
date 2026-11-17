import XCTest
@testable import NetworkPNTRCore

final class AgentPromptInspectionTests: XCTestCase {
    @MainActor func testPreviewSendsLiteralDraftAndPreservesRenderDiagnostics() async throws {
        let api = ChatTestTransport()
        let service = AgentCatalogService(client: api)
        let draft = "  {{.Now}}\n日本語\n"
        try api.enqueue(["rendered": "  fixture time\n日本語\n"])
        try api.enqueue(["rendered": "", "error": "template: p:1: undefined variable"])

        let valid = try await service.previewPrompt(key: "reporter", template: draft)
        XCTAssertEqual(valid.rendered, "  fixture time\n日本語\n")
        XCTAssertNil(valid.error)
        let invalid = try await service.previewPrompt(key: "reporter", template: "{{.unknown}}")
        XCTAssertEqual(invalid.error, "template: p:1: undefined variable")
        XCTAssertEqual(api.calls.map(\.method), ["POST", "POST"])
        XCTAssertEqual(api.calls.map(\.path), Array(repeating: "/api/agents/reporter/prompt/preview", count: 2))
        let body = try XCTUnwrap(api.calls.first?.body)
        XCTAssertEqual(try JSONSerialization.jsonObject(with: body) as? [String: String], ["template": draft])
    }

    func testDiffMatchesFrozenOrderingForRepeatedLines() {
        let result = AgentPromptDiff.compare(older: "A\nB\nA\n", current: "A\nA\nB\n")
        XCTAssertEqual(result?.map(\.kind), [.unchanged, .removed, .unchanged, .added, .unchanged])
        XCTAssertEqual(result?.map(\.text), ["A", "B", "A", "B", ""])
    }

    func testDiffUsesByteEqualityAndSplitsOnLFOnly() {
        let result = AgentPromptDiff.compare(older: "é\r\n  keep", current: "e\u{301}\n  keep\n")
        XCTAssertEqual(result?.map(\.kind), [.removed, .added, .unchanged, .added])
        XCTAssertEqual(result?.map { Array($0.text.utf8) },
                       ["é\r", "e\u{301}", "  keep", ""].map { Array($0.utf8) })
        XCTAssertEqual(AgentPromptDiff.compare(older: "", current: "")?.map(\.text), [""])
    }

    func testOversizedDiffFallsBackToOriginalText() {
        let text = Array(repeating: "line", count: 1_100).joined(separator: "\n")
        XCTAssertNil(AgentPromptDiff.compare(older: text, current: text))
    }
}
