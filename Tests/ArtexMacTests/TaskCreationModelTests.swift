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
    func send(method: String, path: String, body: Data?, bearer: String?) async throws -> BackendHTTPResponse {
        calls.append((method,path,body))
        if hold { return try await withCheckedThrowingContinuation { held[path] = $0 } }
        if method != "GET" { return .init(status: mutationStatus, body: createdBody) }
        let value: Any
        switch path {
        case "/api/task-categories": value = ["categories": [["id": 5, "name": "category"]]]
        case "/api/companies": value = [["id": 6, "name": "company"]]
        case "/api/llm/profiles": value = ["profiles": [["id": "7", "name": "first", "model": "m"], ["id": "8", "name": "second", "model": "m"]]]
        case "/api/task-templates": value = ["templates": [["id": 9, "name": "template", "description": "template 中文", "goal": "template 한국어", "category_id": 5, "intercept_rules": []]]]
        default: value = ["tasks": NSNull(), "active": ""]
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
}
