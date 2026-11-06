import XCTest
@testable import ArtexCore

final class AgentVisibilityEditorTests: XCTestCase {
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
