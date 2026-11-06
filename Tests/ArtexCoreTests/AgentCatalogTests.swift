import XCTest
@testable import ArtexCore

final class AgentCatalogTests: XCTestCase {
    @MainActor func testCatalogPreservesWireOrderAndBrowserFieldDefaults() async throws {
        let api = ChatTestTransport()
        try api.enqueue(["agents": [
            ["key": "worker", "name": "执行", "builtin": true, "enabled": true,
             "mcp_count": 3, "skill_count": 2, "tool_count": 5],
            ["key": "custom", "name": "カスタム 설정", "description": "literal 설명",
             "builtin": false, "enabled": false]
        ]])

        let agents = try await AgentCatalogService(client: api).list()
        XCTAssertEqual(api.calls.map(\.method), ["GET"])
        XCTAssertEqual(api.calls.map(\.path), ["/api/agents"])
        XCTAssertNil(api.calls.first?.body)
        XCTAssertEqual(agents.map(\.key), ["worker", "custom"])
        XCTAssertEqual(agents.map(\.enabled), [true, false])
        XCTAssertEqual(agents.map(\.mcpCount), [3, 0])
        XCTAssertEqual(agents.map(\.skillCount), [2, 0])
        XCTAssertEqual(agents.map(\.toolCount), [5, 0])
        XCTAssertEqual(agents[0].displayName(language: .english), "Execution")
        XCTAssertEqual(agents[0].displayName(language: .japanese), "実行")
        XCTAssertEqual(agents[1].displayName(language: .english), "カスタム 설정")
        XCTAssertEqual(agents[1].displayDescription(language: .japanese), "literal 설명")
    }

    @MainActor func testEmptyCatalogAndRetesterLocalization() async throws {
        let api = ChatTestTransport()
        try api.enqueue(["agents": []])
        try api.enqueue(["agents": [
            ["key": "retester", "name": "漏洞复测", "builtin": false, "enabled": true],
            ["key": "worker", "name": "Custom worker", "builtin": false, "enabled": true]
        ]])
        let service = AgentCatalogService(client: api)
        let empty = try await service.list()
        XCTAssertTrue(empty.isEmpty)
        let agents = try await service.list()
        XCTAssertFalse(agents[0].builtin)
        XCTAssertEqual(agents[0].displayName(language: .japanese), "脆弱性の再検証")
        XCTAssertEqual(agents[1].displayName(language: .japanese), "Custom worker")
        XCTAssertEqual(agents[1].displayDescription(language: .english), "")
    }

    @MainActor func testReporterLocalizesOnlyUnmodifiedSeedFields() async throws {
        let api = ChatTestTransport()
        let seed = "취약점 상세 보고서 작성: 취약점을 발견하면 자동으로 트리거되어, 증거와 실행 과정을 조회한 뒤 Markdown 보고서를 작성해 해당 취약점에 기록합니다."
        try api.enqueue(["agents": [
            ["key": "reporter", "name": "보고서 작성", "description": seed,
             "builtin": false, "enabled": true],
            ["key": "another", "name": "보고서 작성", "description": seed,
             "builtin": false, "enabled": true]
        ]])
        try api.enqueue(["agents": [
            ["key": "reporter", "name": "보고서 작성", "description": "내 설명",
             "builtin": false, "enabled": true]
        ]])
        let service = AgentCatalogService(client: api)
        let agents = try await service.list()
        XCTAssertEqual(agents[0].displayName(language: .english), "Report Writer")
        XCTAssertEqual(agents[0].displayName(language: .japanese), "レポート作成")
        XCTAssertTrue(agents[0].displayDescription(language: .japanese).hasPrefix("脆弱性が見つかる"))
        XCTAssertEqual(agents[1].displayName(language: .japanese), "보고서 작성")
        XCTAssertEqual(agents[1].displayDescription(language: .english), seed)

        let edited = try await service.list()
        XCTAssertEqual(edited[0].displayName(language: .english), "Report Writer")
        XCTAssertEqual(edited[0].displayDescription(language: .english), "내 설명")
    }

    @MainActor func testInvalidIdentityAndFailedRequestDoNotBecomeEmptyCatalog() async throws {
        let api = ChatTestTransport()
        let row: [String: Any] = ["key": "same", "name": "Same", "builtin": true, "enabled": true]
        try api.enqueue(["agents": [row, row]])
        try api.enqueue(["error": "private diagnostic"], status: 503)
        let service = AgentCatalogService(client: api)
        do {
            _ = try await service.list()
            XCTFail("Expected invalid response")
        } catch BackendAPIError.invalidResponse {}
        do {
            _ = try await service.list()
            XCTFail("Expected unavailable status")
        } catch BackendAPIError.status(503) {}
    }

    @MainActor func testCancelledRequestDoesNotPublishEvenIfTransportReturnsSuccess() async throws {
        let api = ChatTestTransport()
        api.handler = { _ in
            withUnsafeCurrentTask { $0?.cancel() }
            return try ChatTestTransport.response(["agents": []])
        }
        let request = Task { try await AgentCatalogService(client: api).list() }
        do {
            _ = try await request.value
            XCTFail("Expected cancellation")
        } catch is CancellationError {}
    }
}
