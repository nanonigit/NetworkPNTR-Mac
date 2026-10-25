import ArtexCore
import SwiftUI
import AppKit
import XCTest
@testable import ArtexMac

@MainActor private final class CreationTestAPI: BackendJSONTransport {
    var calls: [(String,String,Data?)] = []
    var hold = false
    var held: [String: CheckedContinuation<BackendHTTPResponse, any Error>] = [:]
    var mutationStatus = 503
    var createdBody = Data()
    var failPaths = Set<String>()
    var sourceRecords: [[String: Any]] = []
    var templateDescription = "template 中文"
    var templateGoal = "template 한국어"
    func send(method: String, path: String, body: Data?, bearer: String?) async throws -> BackendHTTPResponse {
        calls.append((method,path,body))
        if hold { return try await withCheckedThrowingContinuation { held[path] = $0 } }
        if method != "GET" { return .init(status: mutationStatus, body: createdBody) }
        if failPaths.contains(path) { return .init(status:503,body:Data()) }
        let value: Any
        switch path {
        case "/api/task-categories": value = ["categories": [["id": 5, "name": "category"]]]
        case "/api/companies": value = [["id": 6, "name": "company"]]
        case "/api/llm/profiles": value = ["profiles": [["id": "7", "name": "first", "model": "m"], ["id": "8", "name": "second", "model": "m"]]]
        case "/api/task-templates": value = ["templates": [["id": 9, "name": "template", "description": templateDescription, "goal": templateGoal, "category_id": 5, "intercept_rules": []]]]
        default: value = ["tasks": sourceRecords, "active": ""]
        }
        return .init(status: 200, body: try JSONSerialization.data(withJSONObject: value))
    }
}
final class TaskCreationModelTests: XCTestCase {
    @MainActor private func make() -> (CreationTestAPI, TaskCreationModel) {
        let api = CreationTestAPI()
        return (api, TaskCreationModel(store: TaskStore(service: TaskService(client: api)), service: TaskCreationService(client: api)))
    }
    @MainActor private func reached(_ condition: () -> Bool) async throws {
        for _ in 0..<10_000 { if condition() { return }; await Task.yield() }; XCTFail("Missing suspension"); throw CancellationError()
    }
    @MainActor func testCatalogsTemplatesOrderedProfilesAndCancelPreserveDraft() async throws {
        let (api, model) = make(); let id = try XCTUnwrap(model.open())
        await model.load(contextID: id)
        XCTAssertEqual(api.calls.count, 5); XCTAssertTrue(api.calls.allSatisfy { $0.0 == "GET" })
        model.update(\.draft.name, value: "keep", contextID: id)
        model.toggle(\.draft.llmProfileIds, value: Int64(7), maximum: 100, contextID: id)
        model.toggle(\.draft.llmProfileIds, value: Int64(8), maximum: 100, contextID: id)
        model.moveProfile(id: 8, offset: -1, contextID: id)
        model.chooseTemplate(9, contextID: id)
        XCTAssertEqual(model.form.draft.llmProfileIds, [8,7]); XCTAssertEqual(model.form.draft.name,"keep")
        XCTAssertEqual(model.form.draft.description,"template 中文")
        model.close(contextID: id); let next = try XCTUnwrap(model.open())
        XCTAssertEqual(model.form.draft.name,"keep"); XCTAssertNotEqual(next,id)
        model.update(\.draft.name, value: "stale", contextID: id); XCTAssertEqual(model.form.draft.name,"keep")
        let stale = TaskCreationBindings.field(model: model, contextID: id, key: \.draft.name, fallback: "")
        stale.wrappedValue = "late"; XCTAssertEqual(stale.wrappedValue, ""); XCTAssertEqual(model.form.draft.name,"keep")
    }
    @MainActor func testUnknownCreateRetainsDraftAndBlocksResubmitAcrossReopen() async throws {
        let (api, model) = make(); let id = try XCTUnwrap(model.open())
        model.update(\.draft.description,value:"d",contextID:id); model.update(\.draft.goal,value:"g",contextID:id)
        let result = await model.submit(contextID:id); XCTAssertFalse(result); XCTAssertTrue(model.uncertain)
        model.close(contextID:id); let next = try XCTUnwrap(model.open())
        let repeated = await model.submit(contextID:next); XCTAssertFalse(repeated)
        XCTAssertEqual(api.calls.filter { $0.0 == "POST" }.count,1); XCTAssertEqual(model.form.draft.goal,"g")
        model.update(\.draft.goal,value:"late",contextID:next); XCTAssertEqual(model.form.draft.goal,"g")
        model.discard(contextID:next); XCTAssertNil(model.context); XCTAssertEqual(model.form.draft.goal,""); XCTAssertFalse(model.uncertain)
    }
    @MainActor func testOldCatalogRepliesAndResetCannotChangeNewContext() async throws {
        let (api, model) = make(); let first = try XCTUnwrap(model.open()); api.hold = true
        let load = Task { await model.load(contextID:first) }; try await reached { api.held.count == 5 }
        model.close(contextID:first); let second = try XCTUnwrap(model.open()); model.update(\.draft.name,value:"B",contextID:second)
        let replies = api.held; api.held = [:]; api.hold = false
        for reply in replies.values { reply.resume(throwing: BackendAPIError.status(503)) }
        await load.value; XCTAssertFalse(model.isLoading); XCTAssertNil(model.categories.failure); XCTAssertEqual(model.form.draft.name,"B")
        model.reset(); XCTAssertNil(model.context); XCTAssertEqual(model.form.draft.name,"")
    }
    @MainActor func testConfirmedCreationClearsOnlyItsOwnDraftDespiteRefreshAndNoActivation() async throws {
        let (api, model) = make(); let id = try XCTUnwrap(model.open())
        model.update(\.draft.description,value:"d",contextID:id); model.update(\.draft.goal,value:"g",contextID:id)
        let url = URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("ArtexCoreTests/Fixtures/task-contract.json")
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with:Data(contentsOf:url)) as? [String:Any])
        api.createdBody = try JSONSerialization.data(withJSONObject:XCTUnwrap(root["task"])); api.mutationStatus = 201
        let result = await model.submit(contextID:id); XCTAssertTrue(result); XCTAssertNil(model.context); XCTAssertEqual(model.form.draft.goal,"")
        XCTAssertEqual(api.calls.filter { $0.0 == "POST" }.count,1); XCTAssertFalse(api.calls.contains { $0.1 == "/api/active" })
    }
    @MainActor func testCreationViewRetainsFieldsAcrossLanguageAndParentReset() async throws {
        let api = CreationTestAPI(); let store = TaskStore(service: TaskService(client: api))
        let parent = TaskScreenModel(store: store, creationService: TaskCreationService(client: api))
        XCTAssertTrue(parent.beginCreate()); let model = try XCTUnwrap(parent.creation); let id = try XCTUnwrap(model.context).id
        await model.load(contextID:id)
        model.update(\.draft.description,value:"literal 中文 한국어",contextID:id); model.update(\.draft.goal,value:"goal",contextID:id)
        model.addRule(contextID:id)
        for language in AppLanguage.allCases {
            let hosting = NSHostingView(rootView: TaskCreateView(model:model,contextID:id).environment(\.locale,language.locale))
            hosting.frame = NSRect(x:0,y:0,width:650,height:700); hosting.layoutSubtreeIfNeeded()
            XCTAssertTrue(hosting.fittingSize.width.isFinite); XCTAssertNil(hosting.window)
            XCTAssertEqual(model.form.draft.description,"literal 中文 한국어")
        }
        XCTAssertEqual(api.calls.filter { $0.0 == "POST" }.count,0)
        parent.reset(); XCTAssertNil(model.context); XCTAssertEqual(model.form.draft.description,"")
    }

    private func fixture() throws -> [String:Any] {
        let url = URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("ArtexCoreTests/Fixtures/task-contract.json")
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with:Data(contentsOf:url)) as? [String:Any])
        return try XCTUnwrap(root["task"] as? [String:Any])
    }
    @MainActor func testNativeFormSendsEveryOptionAndPreservesOrderWithoutActivation() async throws {
        let (api, model) = make(); api.sourceRecords = [try fixture()]; let id = try XCTUnwrap(model.open())
        await model.load(contextID:id)
        model.update(\.draft.name,value:" name ",contextID:id); model.update(\.draft.description,value:" desc ",contextID:id); model.update(\.draft.goal,value:" goal ",contextID:id)
        model.update(\.draft.categoryId,value:Int64(5),contextID:id)
        model.setSelected(\.draft.llmProfileIds,value:Int64(7),selected:true,maximum:100,contextID:id)
        model.setSelected(\.draft.llmProfileIds,value:Int64(7),selected:true,maximum:100,contextID:id)
        model.setSelected(\.draft.llmProfileIds,value:Int64(8),selected:true,maximum:100,contextID:id); model.moveProfile(id:8,offset:-1,contextID:id)
        model.toggle(\.draft.companyIds,value:Int64(6),maximum:32,contextID:id)
        model.toggle(\.draft.sourceTaskIds,value:"9007199254740993",maximum:8,contextID:id)
        model.update(\.timeoutMinutes,value:"2.9",contextID:id); model.update(\.heartbeatMinutes,value:"1",contextID:id)
        model.update(\.draft.seedFirstIntent,value:true,contextID:id); model.update(\.draft.coverageEnabled,value:false,contextID:id)
        model.addRule(contextID:id); let rule = try XCTUnwrap(model.form.rules.first).id
        model.updateRule(id:rule,key:\.action,value:.allow,contextID:id); model.updateRule(id:rule,key:\.kind,value:.cidr,contextID:id)
        model.updateRule(id:rule,key:\.pattern,value:" 10.0.0.0/8 ",contextID:id); model.updateRule(id:rule,key:\.note,value:"literal",contextID:id)
        _ = await model.submit(contextID:id)
        let sent = try XCTUnwrap(api.calls.first(where:{$0.0 == "POST"}))
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with:XCTUnwrap(sent.2)) as? [String:Any])
        XCTAssertEqual(body.count,12); XCTAssertEqual(body["name"] as? String,"name"); XCTAssertEqual(body["description"] as? String,"desc"); XCTAssertEqual(body["goal"] as? String,"goal")
        XCTAssertEqual(body["category_id"] as? Int,5); XCTAssertEqual(body["company_ids"] as? [Int],[6]); XCTAssertEqual(body["llm_profile_ids"] as? [Int],[8,7])
        XCTAssertEqual(body["source_task_ids"] as? [String],["9007199254740993"]); XCTAssertEqual(body["timeout_seconds"] as? Int,120); XCTAssertEqual(body["plan_heartbeat_seconds"] as? Int,600)
        XCTAssertEqual(body["seed_first_intent"] as? Bool,true); XCTAssertEqual(body["coverage_enabled"] as? Bool,false)
        let rules = try XCTUnwrap(body["intercept_rules"] as? [[String:Any]]); XCTAssertEqual(rules[0]["kind"] as? String,"cidr"); XCTAssertEqual(rules[0]["pattern"] as? String,"10.0.0.0/8")
        XCTAssertEqual(api.calls.filter{$0.0 == "POST"}.count,1); XCTAssertFalse(api.calls.contains{$0.1 == "/api/active"})
    }
    @MainActor func testPendingCreateGateAndParentResetDiscardLateConfirmation() async throws {
        let api = CreationTestAPI(); let store = TaskStore(service:TaskService(client:api)); let parent = TaskScreenModel(store:store,creationService:TaskCreationService(client:api))
        XCTAssertTrue(parent.beginCreate()); let model = try XCTUnwrap(parent.creation); let id = try XCTUnwrap(model.context).id
        model.update(\.draft.description,value:"d",contextID:id); model.update(\.draft.goal,value:"g",contextID:id)
        api.hold = true; let pending = Task { await model.submit(contextID:id) }; try await reached { api.held["/api/tasks"] != nil }
        XCTAssertTrue(parent.busy); XCTAssertFalse(parent.beginCreate())
        let repeated = await model.submit(contextID:id); XCTAssertFalse(repeated); XCTAssertEqual(api.calls.count,1)
        model.update(\.draft.goal,value:"late",contextID:id); XCTAssertEqual(model.form.draft.goal,"g")
        parent.reset(); XCTAssertNil(model.context); XCTAssertTrue(model.isSubmitting)
        api.hold = false; try XCTUnwrap(api.held["/api/tasks"]).resume(returning:.init(status:201,body:JSONSerialization.data(withJSONObject:fixture())))
        let accepted = await pending.value; XCTAssertFalse(accepted); XCTAssertNil(store.lastConfirmation); XCTAssertFalse(parent.busy)
        XCTAssertTrue(parent.beginCreate()); XCTAssertEqual(model.form.draft.goal,"")
        let newID = try XCTUnwrap(model.context).id
        let oldConfirm = await model.submit(contextID:id); XCTAssertFalse(oldConfirm); model.close(contextID:id); XCTAssertEqual(model.context?.id,newID)
    }
    @MainActor func testRefreshFailuresRetainChoicesAndRemovedRuleCallbacksDoNothing() async throws {
        let (api, model) = make(); let id = try XCTUnwrap(model.open()); await model.load(contextID:id)
        model.toggle(\.draft.llmProfileIds,value:Int64(7),maximum:100,contextID:id)
        api.failPaths = ["/api/llm/profiles"]; await model.load(contextID:id)
        XCTAssertNotNil(model.profiles.failure); XCTAssertEqual(model.profiles.value?.map(\.id),[7,8]); XCTAssertEqual(model.form.draft.llmProfileIds,[7])
        model.addRule(contextID:id); let removed = try XCTUnwrap(model.form.rules.first).id
        let stale = TaskCreationBindings.rule(model:model,contextID:id,ruleID:removed,key:\.pattern,fallback:"")
        model.removeRule(id:removed,contextID:id); model.addRule(contextID:id)
        stale.wrappedValue = "late"; XCTAssertEqual(stale.wrappedValue,""); XCTAssertEqual(model.form.rules[0].rule.pattern,"")
        model.chooseTemplate(9,contextID:id); model.chooseTemplate(nil,contextID:id)
        XCTAssertNil(model.selectedTemplateID); XCTAssertEqual(model.form.draft.description,"template 中文")
        model.update(\.draft.categoryId,value:Int64(999),contextID:id)
        let before = api.calls.count; let accepted = await model.submit(contextID:id)
        XCTAssertFalse(accepted); XCTAssertEqual(api.calls.count,before); XCTAssertNotNil(model.failure)
    }

    @MainActor func testTemplateSelectionPreservesEditedFieldsUntilOverwriteDecision() async throws {
        let (_, model) = make(); let id = try XCTUnwrap(model.open()); await model.load(contextID:id)
        model.update(\.draft.description,value:"edited description",contextID:id); model.update(\.draft.goal,value:"edited goal",contextID:id)
        model.addRule(contextID:id)
        model.chooseTemplate(9,contextID:id)
        XCTAssertEqual(model.form.draft.description,"edited description"); XCTAssertEqual(model.form.draft.goal,"edited goal"); XCTAssertEqual(model.form.rules.count,1)
        let first = try XCTUnwrap(model.pendingTemplate).id
        let blocked = await model.submit(contextID:id); XCTAssertFalse(blocked)
        model.resolveTemplate(id:first,apply:false,contextID:id)
        XCTAssertNil(model.pendingTemplate); XCTAssertEqual(model.form.draft.description,"edited description"); XCTAssertEqual(model.form.rules.count,1)
        model.chooseTemplate(9,contextID:id); let accepted = try XCTUnwrap(model.pendingTemplate).id
        model.resolveTemplate(id:accepted,apply:true,contextID:id)
        XCTAssertEqual(model.form.draft.description,"template 中文"); XCTAssertEqual(model.form.draft.categoryId,5); XCTAssertEqual(model.form.rules.count,0)
        model.update(\.draft.description,value:"new edit",contextID:id); model.chooseTemplate(9,contextID:id)
        let stale = try XCTUnwrap(model.pendingTemplate).id
        model.close(contextID:id); let next = try XCTUnwrap(model.open()); model.chooseTemplate(9,contextID:next)
        let current = try XCTUnwrap(model.pendingTemplate).id
        model.resolveTemplate(id:stale,apply:true,contextID:next)
        XCTAssertEqual(model.pendingTemplate?.id,current); XCTAssertEqual(model.form.draft.description,"new edit")
        model.resolveTemplate(id:current,apply:false,contextID:next)
        XCTAssertEqual(model.form.draft.description,"new edit"); XCTAssertNil(model.pendingTemplate)
    }

    @MainActor func testCanonicalEquivalentTemplateTextStillRequiresByteExactConfirmation() async throws {
        for descriptionField in [true,false] {
            for (existing,replacement) in [("é","e\u{301}"),("e\u{301}","é")] {
                let (api,model) = make(); api.templateDescription = descriptionField ? replacement : "d"; api.templateGoal = descriptionField ? "g" : replacement
                let id = try XCTUnwrap(model.open()); await model.load(contextID:id)
                model.update(\.draft.description,value:descriptionField ? existing : "d",contextID:id)
                model.update(\.draft.goal,value:descriptionField ? "g" : existing,contextID:id)
                model.addRule(contextID:id); model.chooseTemplate(9,contextID:id)
                XCTAssertNotNil(model.pendingTemplate)
                XCTAssertEqual(Array((descriptionField ? model.form.draft.description : model.form.draft.goal).utf8),Array(existing.utf8))
                XCTAssertEqual(model.form.rules.count,1)
            }
        }
    }

}
