import XCTest
import Observation
@testable import ArtexCore
@testable import ArtexMac

@MainActor private final class LLMEditorBackend: BackendJSONTransport {
    var calls: [(String, String, Data?)] = []
    var hold = false
    var pending: CheckedContinuation<BackendHTTPResponse, any Error>?
    var responses: [BackendHTTPResponse] = []
    func queue(_ text: String, status: Int = 200) { responses.append(.init(status: status, body: Data(text.utf8))) }
    func fullLoad() throws {
        queue("{\"profiles\":[]}"); queue("{\"enabled\":false,\"bind_fallback\":false,\"chain\":[]}")
        responses.append(.init(status: 200, body: try LLMWire.encode(LLMRetryPolicy())))
    }
    func send(method: String, path: String, body: Data?, bearer: String?) async throws -> BackendHTTPResponse {
        XCTAssertNil(bearer); calls.append((method, path, body))
        if hold { hold = false; return try await withCheckedThrowingContinuation { pending = $0 } }
        guard !responses.isEmpty else { throw BackendAPIError.invalidResponse }
        return responses.removeFirst()
    }
    func finish(_ text: String, status: Int = 200) {
        let value = pending; pending = nil
        value?.resume(returning: .init(status: status, body: Data(text.utf8)))
    }
}

final class LLMEditorModelTests: XCTestCase {
    @MainActor private func make() -> (LLMEditorBackend, LLMStore, LLMEditorModel) {
        let api = LLMEditorBackend(); let store = LLMStore(service: LLMService(client: api))
        var draft = LLMProfileDraft(); draft.id = 7; draft.name = "\u{feff}e\u{301} 中文 한국어"; draft.model = "fixture"
        draft.apiKey = "synthetic-key"; draft.proxy = "https://synthetic.invalid"
        return (api, store, LLMEditorModel(store: store, draft: draft))
    }
    @MainActor private func reached(_ condition: () -> Bool) async throws {
        for _ in 0..<2000 { if condition() { return }; try await Task.sleep(for: .milliseconds(1)) }
        XCTFail("Editor did not reach the expected phase")
    }
    @MainActor func testClosingBeforeTaskStartsPreventsAllThreeDispatchFamiliesAndClearsSecrets() async throws {
        for kind in 0..<3 {
            let (api, store, model) = make()
            let accepted = kind == 0 ? model.fetchModels() : kind == 1 ? model.testConnection() : model.save()
            XCTAssertTrue(accepted); model.close(); model.close()
            try await reached { !model.isBusy }
            XCTAssertTrue(api.calls.isEmpty); XCTAssertNil(store.unknownRevision)
            XCTAssertEqual(model.draft.apiKey, ""); XCTAssertEqual(model.draft.proxy, "")
            XCTAssertFalse(model.isActive); XCTAssertFalse(model.didSave); XCTAssertNil(model.failure)
            XCTAssertFalse(model.fetchModels()); XCTAssertFalse(model.testConnection()); XCTAssertFalse(model.save())
        }
    }
    @MainActor func testLateModelAndProbeSuccessAfterCloseCannotPublishOrReleaseGateEarly() async throws {
        for models in [true, false] {
            let (api, _, model) = make(); api.hold = true
            XCTAssertTrue(models ? model.fetchModels() : model.testConnection())
            try await reached { api.pending != nil }
            model.close(); model.activate(); XCTAssertTrue(model.isBusy)
            XCTAssertFalse(model.fetchModels()); XCTAssertFalse(model.save())
            api.finish(models ? "{\"ok\":true,\"models\":[\"obsolete\"]}" : "{\"ok\":true,\"reply\":\"obsolete\",\"model\":\"fixture\"}")
            try await reached { !model.isBusy }
            XCTAssertTrue(model.models.isEmpty); XCTAssertFalse(model.modelsOpen)
            XCTAssertNil(model.testResult); XCTAssertNil(model.failure); XCTAssertFalse(model.didSave)
        }
    }
    @MainActor func testDraftMutationCancelsHeldProbeAndPreservesExactCustomBytes() async throws {
        let (api, _, model) = make(); api.hold = true
        XCTAssertTrue(model.testConnection()); try await reached { api.pending != nil }
        model.draft.name = "\u{feff}é 中文 한국어"
        XCTAssertTrue(model.isBusy)
        api.finish("{\"ok\":true,\"reply\":\"obsolete\"}")
        try await reached { !model.isBusy }
        XCTAssertNil(model.testResult); XCTAssertNil(model.failure)
        XCTAssertEqual(Data(model.draft.name.utf8), Data("\u{feff}é 中文 한국어".utf8))
        api.queue("{\"ok\":true,\"models\":[\"literal 中文 한국어\"]}")
        XCTAssertTrue(model.fetchModels()); try await reached { !model.isBusy }
        XCTAssertEqual(model.models, ["literal 中文 한국어"])
        model.draft.apiKey = "another-synthetic-key"
        XCTAssertTrue(model.models.isEmpty); XCTAssertFalse(model.modelsOpen)
    }
    @MainActor func testCurrentProbeSuccessAndFailureUseActualContractsWithoutAutomaticCalls() async throws {
        let (api, _, model) = make()
        api.queue("{\"ok\":true,\"reply\":\"fixture reply\",\"model\":\"fixture\",\"latency_ms\":2}")
        XCTAssertTrue(model.testConnection()); XCTAssertFalse(model.fetchModels())
        try await reached { !model.isBusy }
        XCTAssertEqual(model.testResult?.reply, "fixture reply"); XCTAssertNil(model.failure)
        let request = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(api.calls.first?.2)) as? [String: Any])
        XCTAssertEqual(request["profile_id"] as? Int, 7)
        api.queue("{\"error\":\"raw synthetic-key\"}", status: 503)
        XCTAssertTrue(model.testConnection()); try await reached { !model.isBusy }
        XCTAssertNil(model.testResult); XCTAssertNotNil(model.failure)
        XCTAssertFalse(model.failure?.text(language: .english).contains("synthetic-key") ?? true)
        XCTAssertEqual(api.calls.count, 2)
    }
    @MainActor func testConfirmedSaveScrubsKeyAndOnlyCurrentEditorPublishesDismissalReceipt() async throws {
        let (api, _, model) = make(); api.queue("{\"id\":7}"); try api.fullLoad()
        XCTAssertTrue(model.save()); try await reached { !model.isBusy }
        XCTAssertTrue(model.didSave); XCTAssertEqual(model.draft.apiKey, "")
        model.draft.name = "new unsaved draft"
        XCTAssertFalse(model.didSave)
        XCTAssertEqual(api.calls.filter { $0.0 == "POST" }.count, 1)
    }
    @MainActor func testClosingDispatchedSavePreservesStoreUncertaintyButNeverDismissesReopenedEditor() async throws {
        let (api, store, model) = make(); api.hold = true
        XCTAssertTrue(model.save()); try await reached { api.pending != nil }
        model.close(); model.activate(); XCTAssertTrue(store.isMutating)
        XCTAssertFalse(model.save()); api.finish("{\"id\":7}")
        try await reached { !model.isBusy }
        XCTAssertNotNil(store.unknownRevision); XCTAssertFalse(model.didSave); XCTAssertNil(model.failure)
    }
}
