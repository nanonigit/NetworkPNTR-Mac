import XCTest
@testable import ArtexCore
final class TaskCreationTests: XCTestCase {
    @MainActor func testOptionContractsKeepExactIDsAndIgnoreCredentials() async throws {
        let api = ChatTestTransport(); let service = TaskCreationService(client: api)
        try api.enqueue(["categories": [["id": 9_007_199_254_740_993, "name": "literal 中文 한국어"]]])
        let categories = try await service.categories(); XCTAssertEqual(categories[0].id, 9_007_199_254_740_993)
        try api.enqueue([["id": 7, "name": "company"]]); let companies = try await service.companies(); XCTAssertEqual(companies.count, 1)
        try api.enqueue(["profiles": [["id": 8, "name": "profile", "model": "model", "api_key": "private-secret"]]])
        let profiles = try await service.profiles(); XCTAssertFalse(String(describing: profiles).contains("private-secret"))
        try api.enqueue(["templates": [["id": 3, "name": "template", "description": "d", "goal": "g", "category_id": NSNull(), "intercept_rules": NSNull()]]])
        let templates = try await service.templates(); XCTAssertTrue(templates[0].interceptRules.isEmpty)
        XCTAssertEqual(api.calls.map(\.path), ["/api/task-categories", "/api/companies", "/api/llm/profiles", "/api/task-templates"])
        XCTAssertTrue(api.calls.allSatisfy { $0.method == "GET" && $0.body == nil })
    }
    @MainActor func testMalformedCatalogsNeverBecomeValidChoices() async throws {
        let api = ChatTestTransport(); let service = TaskCreationService(client: api)
        for body in [["bad": []], ["categories": "wrong"], ["categories": [["id": 0, "name": "x"]]], ["categories": [["id": 7, "name": "x"], ["id": 7, "name": "y"]]]] as [[String: Any]] {
            try api.enqueue(body); do { _ = try await service.categories(); XCTFail("Malformed accepted") } catch {}
        }
        try api.enqueue(["categories": NSNull()]); let empty = try await service.categories(); XCTAssertTrue(empty.isEmpty)
        try api.enqueue(["error": "private-secret"], status: 503)
        do { _ = try await service.profiles(); XCTFail("Failure accepted") } catch { XCTAssertFalse(error.localizedDescription.contains("private-secret")) }
        try api.enqueue(["templates": [["id": 3, "name": "t", "description": "d", "goal": "g", "intercept_rules": [["enabled": true, "action": "allow", "kind": "unknown", "pattern": "x", "note": ""]]]]])
        do { _ = try await service.templates(); XCTFail("Unknown rule dropped") } catch {}
    }
    func testFormMinutesAndTemplatePreserveUnrelatedSettings() throws {
        var form = TaskCreationForm(); form.draft.description = "d"; form.draft.goal = "g"
        XCTAssertEqual(try form.payload().planHeartbeatSeconds, 600)
        form.timeoutMinutes = "2.9"; form.heartbeatMinutes = "1"
        XCTAssertEqual(try form.payload().timeoutSeconds, 120); XCTAssertEqual(try form.payload().planHeartbeatSeconds, 600)
        for invalid in ["1junk", "NaN", "Infinity", "9223372036854775807", "1e999"] {
            form.timeoutMinutes = invalid; XCTAssertThrowsError(try form.payload())
        }
        form.timeoutMinutes = ""; form.draft.name = "keep"; form.draft.llmProfileIds = [8,7]; form.draft.companyIds = [4]
        let data = Data(#"{"id":3,"name":"t","description":"template 中文","goal":"goal 한국어","category_id":5,"intercept_rules":[{"enabled":true,"action":"allow","kind":"cidr","pattern":"10.0.0.0/8","note":"literal"}]}"#.utf8)
        let template = try BackendJSONCoding.decode(TaskTemplateOption.self, from: data)
        form.apply(template); let payload = try form.payload()
        XCTAssertEqual(payload.name, "keep"); XCTAssertEqual(payload.llmProfileIds, [8,7]); XCTAssertEqual(payload.companyIds, [4])
        XCTAssertEqual(payload.description, "template 中文"); XCTAssertEqual(payload.categoryId, 5); XCTAssertEqual(payload.interceptRules[0].kind, .cidr)
        XCTAssertEqual(form.rules.count, 1)
    }
}
