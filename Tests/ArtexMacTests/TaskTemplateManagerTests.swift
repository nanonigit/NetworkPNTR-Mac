import Foundation
import XCTest
@testable import ArtexCore
@testable import ArtexMac

@MainActor private final class TemplateManagerAPI: BackendJSONTransport {
    var status = 200
    var hold = false
    var holdReads = false
    var failReads = false
    var calls: [(String,String,Data?)] = []
    var held: [CheckedContinuation<BackendHTTPResponse,Error>] = []
    var reads: [String:CheckedContinuation<BackendHTTPResponse,Error>] = [:]
    func row(_ id: Int64, description: String = "e\u{301} 中文 한국어") throws -> TaskTemplateOption {
        try BackendJSONCoding.decode(TaskTemplateOption.self,from:data(id,description:description))
    }
    func data(_ id: Int64, description: String = "saved description") throws -> Data {
        try JSONSerialization.data(withJSONObject:["id":id,"name":"template \(id)","description":description,"goal":"goal","category_id":NSNull(),"intercept_rules":[]])
    }
    func send(method: String, path: String, body: Data?, bearer: String?) async throws -> BackendHTTPResponse {
        calls.append((method,path,body))
        if method == "GET" {
            if holdReads { return try await withCheckedThrowingContinuation { reads[path] = $0 } }
            if failReads { return .init(status:503,body:Data()) }
            return .init(status:200,body:Data((path == "/api/task-templates" ? #"{"templates":[]}"# : #"{"categories":[]}"#).utf8))
        }
        if hold { return try await withCheckedThrowingContinuation { held.append($0) } }
        if status != 200 { return .init(status:status,body:Data("private server text".utf8)) }
        if method == "DELETE" { return .init(status:200,body:Data(#"{"deleted":7}"#.utf8)) }
        return .init(status:method == "POST" ? 201 : 200,body:try data(method == "POST" ? 9 : 7))
    }
}

final class TaskTemplateManagerTests: XCTestCase {
    @MainActor private func make() -> (TemplateManagerAPI,TaskTemplateManager) {
        let api = TemplateManagerAPI(); return (api,TaskTemplateManager(service:TaskTemplateService(client:api)))
    }
    private func seed() -> TaskTemplateDraft { var value = TaskTemplateDraft(); value.description = "seed description"; value.goal = "seed goal"; return value }
    @MainActor private func reached(_ condition: () -> Bool) async throws {
        for _ in 0..<10_000 { if condition() { return }; await Task.yield() }; XCTFail("Missing suspension"); throw CancellationError()
    }
    @MainActor func testDirtySelectionAndStaleEditorRuleCallbacks() async throws {
        let (api,model) = make(); let context = try XCTUnwrap(model.open(seed:nil,templates:[try api.row(7),try api.row(8)])), editor = model.editorID
        model.update(\.name,value:"edited",contextID:context,editorID:editor)
        model.addRule(contextID:context,editorID:editor); let rule = try XCTUnwrap(model.form.rules.first).id
        model.requestSelection(8,contextID:context,editorID:editor)
        let cancelled = try XCTUnwrap(model.pendingDecision).id
        _ = await model.resolveDecision(id:cancelled,confirm:false,contextID:context)
        XCTAssertEqual(model.form.name,"edited"); XCTAssertEqual(model.selectedID,7)
        model.requestSelection(8,contextID:context,editorID:editor)
        let decision = try XCTUnwrap(model.pendingDecision).id
        _ = await model.resolveDecision(id:decision,confirm:true,contextID:context)
        XCTAssertEqual(model.selectedID,8); XCTAssertNotEqual(model.editorID,editor)
        model.update(\.name,value:"late",contextID:context,editorID:editor)
        model.updateRule(id:rule,key:\.pattern,value:"late",contextID:context,editorID:editor)
        XCTAssertEqual(model.form.name,"template 8"); XCTAssertTrue(model.form.rules.isEmpty); XCTAssertTrue(api.calls.isEmpty)
    }
    @MainActor func testSeedSaveReceiptSurvivesReadFailureAndDoesNotCreateTask() async throws {
        let (api,model) = make(); var receipts = 0; model.onReceipt = { _ in receipts += 1 }
        let context = try XCTUnwrap(model.open(seed:seed(),templates:[])), editor = model.editorID
        XCTAssertEqual(model.form.name,""); XCTAssertEqual(model.form.description,"seed description")
        model.update(\.name,value:"saved",contextID:context,editorID:editor)
        let result = await model.save(contextID:context,editorID:editor)
        XCTAssertTrue(result); XCTAssertEqual(model.selectedID,9); XCTAssertEqual(model.templates.first?.id,9); XCTAssertFalse(model.isDirty); XCTAssertEqual(receipts,1)
        api.failReads = true; await model.load(contextID:context)
        XCTAssertEqual(model.templates.first?.id,9); XCTAssertNotNil(model.listFailure)
        XCTAssertEqual(api.calls.filter { $0.0 == "POST" }.count,1); XCTAssertFalse(api.calls.contains { $0.1 == "/api/tasks" })
    }
    @MainActor func testUnknownMutationRetainsDraftAcrossReopenUntilExplicitLocalDiscard() async throws {
        let (api,model) = make(); api.status = 503
        var context = try XCTUnwrap(model.open(seed:seed(),templates:[])); model.update(\.name,value:"keep",contextID:context,editorID:model.editorID)
        let result = await model.save(contextID:context,editorID:model.editorID); XCTAssertFalse(result); XCTAssertTrue(model.uncertain)
        model.close(contextID:context); context = try XCTUnwrap(model.open(seed:nil,templates:[]))
        let repeated = await model.save(contextID:context,editorID:model.editorID); XCTAssertFalse(repeated); XCTAssertEqual(api.calls.count,1); XCTAssertEqual(model.form.name,"keep")
        model.requestLocalDiscard(contextID:context)
        let decision = try XCTUnwrap(model.pendingDecision).id
        _ = await model.resolveDecision(id:decision,confirm:true,contextID:context)
        XCTAssertFalse(model.uncertain); XCTAssertEqual(model.form.name,""); XCTAssertEqual(api.calls.count,1)
        model.update(\.name,value:"correct",contextID:context,editorID:model.editorID); model.update(\.description,value:"d",contextID:context,editorID:model.editorID); model.update(\.goal,value:"g",contextID:context,editorID:model.editorID)
        api.status = 409
        let conflict = await model.save(contextID:context,editorID:model.editorID); XCTAssertFalse(conflict); XCTAssertFalse(model.uncertain)
        XCTAssertEqual(model.failure?.text(language:.english),AppStrings.text(.taskTemplateConflict,language:.english))
    }
    @MainActor func testDeleteUsesImmutableDecisionAndSelectsRemainingTemplate() async throws {
        let (api,model) = make(); let context = try XCTUnwrap(model.open(seed:nil,templates:[try api.row(7),try api.row(8)])), editor = model.editorID
        model.update(\.name,value:"unsaved name",contextID:context,editorID:editor)
        model.requestDelete(contextID:context,editorID:editor)
        let decision = try XCTUnwrap(model.pendingDecision)
        let stale = await model.resolveDecision(id:UUID(),confirm:true,contextID:context); XCTAssertFalse(stale); XCTAssertTrue(api.calls.isEmpty)
        let deleted = await model.resolveDecision(id:decision.id,confirm:true,contextID:context)
        XCTAssertTrue(deleted); XCTAssertEqual(api.calls.last?.1,"/api/task-templates/7"); XCTAssertEqual(model.selectedID,8); XCTAssertEqual(model.form.name,"template 8")
    }
    @MainActor func testResetKeepsMutationGateUntilOldOperationCompletes() async throws {
        let (api,model) = make(); api.hold = true; var receipts = 0; model.onReceipt = { _ in receipts += 1 }
        let context = try XCTUnwrap(model.open(seed:nil,templates:[try api.row(7)])), editor = model.editorID
        let pending = Task { await model.save(contextID:context,editorID:editor) }
        try await reached { api.held.count == 1 }
        model.reset(); XCTAssertTrue(model.isMutating); XCTAssertNil(model.open(seed:nil,templates:[]))
        api.held[0].resume(returning:.init(status:200,body:try api.data(7)))
        let late = await pending.value; XCTAssertFalse(late); XCTAssertEqual(receipts,0); XCTAssertTrue(model.templates.isEmpty); XCTAssertFalse(model.isMutating)
        XCTAssertNotNil(model.open(seed:nil,templates:[]))
    }
    @MainActor func testLateReadsAndByteEquivalentEditsCannotOverwriteReopenedDraft() async throws {
        let (api,model) = make(); api.holdReads = true
        let context = try XCTUnwrap(model.open(seed:nil,templates:[try api.row(7,description:"e\u{301}")]))
        model.update(\.description,value:"é",contextID:context,editorID:model.editorID); XCTAssertTrue(model.isDirty)
        let pending = Task { await model.load(contextID:context) }; try await reached { api.reads.count == 2 }
        model.reset(); let next = try XCTUnwrap(model.open(seed:seed(),templates:[]))
        model.update(\.name,value:"new",contextID:next,editorID:model.editorID)
        api.reads["/api/task-templates"]?.resume(returning:.init(status:200,body:Data(#"{"templates":[]}"#.utf8)))
        api.reads["/api/task-categories"]?.resume(returning:.init(status:200,body:Data(#"{"categories":[]}"#.utf8)))
        await pending.value; XCTAssertEqual(model.form.name,"new"); XCTAssertFalse(model.isLoading)
    }
    @MainActor func testSuspendPreservesConfirmedReceiptWithoutReopeningContext() async throws {
        let (api,model) = make(); api.hold = true
        let context = try XCTUnwrap(model.open(seed:nil,templates:[try api.row(7)])), editor = model.editorID
        let pending = Task { await model.save(contextID:context,editorID:editor) }; try await reached { api.held.count == 1 }
        model.suspend(); XCTAssertNil(model.context); XCTAssertTrue(model.isMutating)
        api.held[0].resume(returning:.init(status:200,body:try api.data(7)))
        let confirmed = await pending.value; XCTAssertTrue(confirmed); XCTAssertNil(model.context); XCTAssertEqual(model.templates.first?.id,7)
    }
}
