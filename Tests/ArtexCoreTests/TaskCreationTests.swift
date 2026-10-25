import XCTest
@testable import ArtexCore
final class TaskCreationTests: XCTestCase {
    @MainActor func testOptionContractsKeepExactIDsAndIgnoreCredentials() async throws {
        let api = ChatTestTransport(); let service = TaskCreationService(client: api)
        try api.enqueue(["categories": [["id": 9_007_199_254_740_993, "name": "literal 中文 한국어"]]])
        let categories = try await service.categories(); XCTAssertEqual(categories[0].id, 9_007_199_254_740_993)
        try api.enqueue([["id": 7, "name": "company"]]); let companies = try await service.companies(); XCTAssertEqual(companies.count, 1)
        try api.enqueue(["profiles": [["id": "8", "name": "profile", "model": "model", "api_key": "private-secret"]]])
        let profiles = try await service.profiles(); XCTAssertEqual(profiles[0].id,8); XCTAssertFalse(String(describing: profiles).contains("private-secret"))
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
    @MainActor func testRawTemplateTextRetainsBOMAndUnicodeBytes() async throws {
        let api = ChatTestTransport(); let service = TaskCreationService(client: api)
        let raw = Data(#"{"templates":[{"id":3,"name":"\uFEFFname","description":"\uFEFFe\u0301中","goal":"\uFEFFé한","category_id":null,"intercept_rules":[]}]}"#.utf8)
        api.replies.append(.init(status:200,body:raw))
        let result = try await service.templates()
        XCTAssertEqual(Array(result[0].name.utf8), Array("\u{FEFF}name".utf8))
        XCTAssertEqual(Array(result[0].description.utf8),Array("\u{FEFF}e\u{301}中".utf8))
        XCTAssertEqual(Array(result[0].goal.utf8),Array("\u{FEFF}é한".utf8))
    }

    func testCreationLabelsAreBilingualCatalogEntries() {
        XCTAssertEqual(AppStrings.text(.taskCreateTitle, language: .english), "New task")
        XCTAssertEqual(AppStrings.text(.taskCreateTitle, language: .japanese), "新しいタスク")
        for key in AppStringKey.allCases where key.rawValue.hasPrefix("task.create.") {
            for language in AppLanguage.allCases { XCTAssertNotEqual(AppStrings.text(key,language:language),key.rawValue) }
        }
    }

    @MainActor func testProfileIDsStatusesBodyBoundsAndPreCancellation() async throws {
        let api = ChatTestTransport(); let service = TaskCreationService(client:api)
        for id in ["0","-1","01","9223372036854775808","１"] {
            try api.enqueue(["profiles":[["id":id,"name":"n","model":"m"]]])
            do { _ = try await service.profiles(); XCTFail("Invalid string ID") } catch {}
        }
        try api.enqueue(["profiles":[["id":"9007199254740993","name":"n","model":"m"]]])
        let large = try await service.profiles(); XCTAssertEqual(large[0].id,9_007_199_254_740_993)
        try api.enqueue(["profiles":[]],status:202)
        do { _ = try await service.profiles(); XCTFail("Accepted unconfirmed status") } catch {}
        let oversized = Data(#"{"profiles":[]}"#.utf8) + Data(repeating:32,count:4*1024*1024)
        api.replies.append(.init(status:200,body:oversized))
        do { _ = try await service.profiles(); XCTFail("Oversized response") } catch {}
        let count = api.calls.count
        let cancelled = Task { @MainActor in try await service.profiles() }; cancelled.cancel()
        do { _ = try await cancelled.value; XCTFail("Cancelled request") } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(api.calls.count,count)
        var form = TaskCreationForm(); form.draft.description = "d"; form.draft.goal = "g"; form.timeoutMinutes = "-1.5"; form.heartbeatMinutes = ""
        XCTAssertEqual(try form.payload().timeoutSeconds,0); XCTAssertEqual(try form.payload().planHeartbeatSeconds,600)
    }

}
