import XCTest
@testable import NetworkPNTRCore

final class AgentVisibilityEditorTests: XCTestCase {
    func testAuthorizedAPIReconDescriptionUsesEnglishAndJapanese() {
        let resource = AgentVisibilityResource(id: .skill("api-recon"), name: "api-recon",
            detail: "在授权范围内发现网站 API、分析参数并验证漏洞、请求修改及访问控制。")
        XCTAssertEqual(resource.displayDetail(language: .english),
            "Discover APIs and validate vulnerabilities, request changes, and access controls within the authorized scope.")
        XCTAssertEqual(resource.displayDetail(language: .japanese),
            "許可された範囲でAPIを調査し、脆弱性・リクエスト変更・アクセス制御を検証します。")
        let edited = AgentVisibilityResource(id: resource.id, name: resource.name, detail: resource.detail! + " custom")
        XCTAssertEqual(edited.displayDetail(language: .japanese), edited.detail)
    }

    func testKnownSkillDescriptionsResolveBothLocalesAndPreserveAuthoredText() {
        let apiDefault = "收集网站API接口时调用该skill。"
        let apiRecon = AgentVisibilityResource(id: .skill("api-recon"), name: "api-recon", detail: apiDefault)
        let browser = AgentVisibilityResource(id: .skill("playwright-cli"), name: "playwright-cli",
                                              detail: "Automate browser interactions, test web pages and work with Playwright tests.")
        XCTAssertEqual(apiRecon.displayDetail(language: .english), "Use this skill to discover a website’s API endpoints.")
        XCTAssertEqual(apiRecon.displayDetail(language: .japanese), "WebサイトのAPIエンドポイントを調べるスキルです。")
        XCTAssertEqual(browser.displayDetail(language: .japanese), "ブラウザ操作の自動化、Webページの検証、Playwrightテストに使います。")
        XCTAssertEqual(browser.displayDetail(language: .english), browser.detail)
        XCTAssertEqual(apiRecon.detail, apiDefault)
        for language in AppLanguage.allCases {
            let edited = AgentVisibilityResource(id: .skill("api-recon"), name: "api-recon", detail: apiDefault + " ")
            let custom = AgentVisibilityResource(id: .skill("custom"), name: "custom", detail: apiDefault)
            let mcp = AgentVisibilityResource(id: .mcp(1), name: "api-recon", detail: apiDefault)
            XCTAssertEqual(edited.displayDetail(language: language), edited.detail)
            XCTAssertEqual(custom.displayDetail(language: language), custom.detail)
            XCTAssertEqual(mcp.displayDetail(language: language), mcp.detail)
        }
    }

    @MainActor func testSkillToggleReadsBackAndWritesOnlyOneAssignment() async throws {
        let api = ChatTestTransport()
        let editor = AgentVisibilityEditor(key: "worker", service: AgentCatalogService(client: api))
        try api.enqueue(["skills": [["name": "fixture", "description": "Test"]]])
        try api.enqueue(["mcp": NSNull(), "skill": ["fixture", "other"]])
        await editor.load(.skill)
        XCTAssertTrue(editor.contains(.skill("fixture")))
        try api.enqueue(["ok": true])
        try api.enqueue(["mcp": [7], "skill": ["other"]])
        await editor.set(.skill("fixture"), visible: false, agentID: "42")

        XCTAssertEqual(api.calls.map(\.path), ["/api/skills", "/api/agents/worker/visibility",
                                                "/api/visibility/skill/toggle", "/api/agents/worker/visibility"])
        let payload = try XCTUnwrap(api.calls[2].body)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: payload) as? [String: Any])
        XCTAssertEqual(Set(object.keys), ["agent_id", "skill_name", "visible"])
        XCTAssertEqual(object["agent_id"] as? String, "42")
        XCTAssertEqual(object["skill_name"] as? String, "fixture")
        XCTAssertEqual(object["visible"] as? Bool, false)
        XCTAssertFalse(editor.contains(.skill("fixture")))
        XCTAssertTrue(editor.contains(.skill("other")))
        XCTAssertTrue(editor.contains(.mcp(7)))
    }

    @MainActor func testMCPMismatchNeedsFreshReadAndDoesNotReplay() async throws {
        let api = ChatTestTransport()
        let editor = AgentVisibilityEditor(key: "worker", service: AgentCatalogService(client: api))
        try api.enqueue(["servers": [["id": 7, "name": "Fixture", "transport": "stdio"]]])
        try api.enqueue(["mcp": NSNull(), "skill": []])
        await editor.load(.mcp)
        try api.enqueue(["ok": true])
        try api.enqueue(["mcp": [], "skill": []])
        await editor.set(.mcp(7), visible: true, agentID: "42")
        await editor.set(.mcp(7), visible: true, agentID: "42")
        XCTAssertEqual(api.calls.map(\.method), ["GET", "GET", "POST", "GET"])
        XCTAssertTrue(editor.requiresReload)
        XCTAssertFalse(editor.contains(.mcp(7)))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(api.calls[2].body)) as? [String: Any])
        XCTAssertEqual(object["kind"] as? String, "mcp")
        XCTAssertEqual(object["resource_id"] as? Int, 7)
    }

    @MainActor func testUnknownRowsAndInvalidAgentIDCannotWrite() async throws {
        let api = ChatTestTransport()
        let editor = AgentVisibilityEditor(key: "worker", service: AgentCatalogService(client: api))
        try api.enqueue(["skills": [["name": "fixture"]]])
        try api.enqueue(["mcp": [], "skill": []])
        await editor.load(.skill)
        await editor.set(.skill("unknown"), visible: true, agentID: "42")
        await editor.set(.skill("fixture"), visible: true, agentID: "worker")
        XCTAssertEqual(api.calls.map(\.method), ["GET", "GET"])
    }
}
