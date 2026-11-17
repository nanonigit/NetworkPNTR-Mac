import XCTest
@testable import NetworkPNTRCore

@MainActor private final class LLMFixtureTransport: BackendJSONTransport {
    var responses: [BackendHTTPResponse] = []
    var calls: [(String, String, Data?)] = []
    func enqueue(_ object: [String: Any]) throws { try enqueue(200, object) }
    func enqueue(_ status: Int, _ object: [String: Any]) throws {
        responses.append(BackendHTTPResponse(status: status, body: try JSONSerialization.data(withJSONObject: object)))
    }
    func send(method: String, path: String, body: Data?, bearer: String?) async throws -> BackendHTTPResponse {
        calls.append((method, path, body))
        guard bearer == nil, !responses.isEmpty else { throw BackendAPIError.invalidResponse }
        return responses.removeFirst()
    }
}
final class LLMServiceTests: XCTestCase {
    @MainActor func testRealMutationPathsAndActiveDeletionGuard() async throws {
        let api = LLMFixtureTransport(); let service = LLMService(client: api)
        var draft = LLMProfileDraft(); draft.name = "fixture"; draft.model = "fixture"
        try api.enqueue(["id": 7])
        let saved = try await service.save(draft)
        XCTAssertEqual(saved, 7)
        try api.enqueue(["ok": true]); try await service.activate(id: "7")
        XCTAssertEqual(api.calls.last?.1, "/api/llm/profiles/active")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(api.calls.last?.2)) as? [String: Int])
        XCTAssertEqual(body["id"], 7)
        do { try await service.delete(id: "7", isActive: true); XCTFail("Active deletion must fail") } catch {}
        XCTAssertEqual(api.calls.count, 2)
        try api.enqueue(["deleted": 7]); try await service.delete(id: "7", isActive: false)
        XCTAssertEqual(api.calls.last?.0, "DELETE")
        XCTAssertEqual(api.calls.last?.1, "/api/llm/profiles/7")
        do { try await service.activate(id: "7/other"); XCTFail("Injected ID must fail") } catch {}
        XCTAssertEqual(api.calls.count, 3)
    }
    @MainActor func testLoadErrorsAndMalformedJSONDoNotBecomeEmptySuccess() async throws {
        let api = LLMFixtureTransport(); let service = LLMService(client: api)
        try api.enqueue(["profiles": []]); let empty = try await service.profiles(); XCTAssertTrue(empty.isEmpty)
        for status in [401, 503] {
            try api.enqueue(status, ["error": "private error detail"])
            do { _ = try await service.profiles(); XCTFail("Status must propagate") }
            catch { XCTAssertFalse(error.localizedDescription.contains("private error detail")) }
        }
        try api.enqueue(["unexpected": true])
        do { _ = try await service.profiles(); XCTFail("Malformed shape must fail") } catch {}
    }
    @MainActor func testModelAndConnectionCallsUseSavedIDAndParametersWithoutLeakingErrors() async throws {
        let api = LLMFixtureTransport(); let service = LLMService(client: api)
        var draft = LLMProfileDraft(); draft.id = 7; draft.name = "fixture"; draft.model = "fixture"
        draft.format = .openaiResponses; draft.streaming = false; draft.sessionHeaderKey = "X-Session"
        draft.thinkingType = "enabled"; draft.reasoningEffort = "high"
        try api.enqueue(["ok": true, "models": ["fixture-model"]])
        let models = try await service.models(draft)
        XCTAssertEqual(models, ["fixture-model"])
        try api.enqueue(["ok": true, "reply": "fixture reply", "latency_ms": 2, "model": "fixture"])
        let test = try await service.test(draft)
        XCTAssertEqual(test.reply, "fixture reply")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(api.calls.last?.2)) as? [String: Any])
        XCTAssertEqual(body["profile_id"] as? Int, 7)
        XCTAssertEqual(body["streaming"] as? Bool, false)
        XCTAssertEqual(body["thinking_type"] as? String, "enabled")
        XCTAssertEqual(body["session_header_key"] as? String, "X-Session")
        try api.enqueue(["ok": false, "error": "sensitive-fixture"])
        do { _ = try await service.test(draft); XCTFail("A 200 failure must not pass") }
        catch { XCTAssertFalse(error.localizedDescription.contains("sensitive-fixture")) }
    }
    @MainActor func testPoolPatchDoesNotReplaceUnrelatedSettingsAndRetryUsesBounds() async throws {
        let api = LLMFixtureTransport(); let service = LLMService(client: api)
        try api.enqueue(["llm_pool_enabled": true])
        try await service.setRotation(enabled: true, bindFallback: nil)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(api.calls.last?.2)) as? [String: Bool])
        XCTAssertEqual(body, ["llm_pool_enabled": true])
        XCTAssertEqual(api.calls.last?.0, "PUT")
        var policy = LLMRetryPolicy(); policy.connect.attempts = 99
        try api.enqueue(try XCTUnwrap(JSONSerialization.jsonObject(with: LLMWire.encode(policy.clamped())) as? [String: Any]))
        let saved = try await service.saveRetry(policy)
        XCTAssertEqual(saved.connect.attempts, 20)
        let sent = try LLMWire.decode(LLMRetryPolicy.self, from: XCTUnwrap(api.calls.last?.2))
        XCTAssertEqual(sent.connect.attempts, 20)
    }
}

extension LLMServiceTests {
    @MainActor func testStoreRetainsExistingProfilesWhenReloadFails() async throws {
        let api = LLMFixtureTransport(); let store = LLMStore(service: LLMService(client: api))
        try api.enqueue(["profiles": [["id": "7", "name": "fixture", "format": "openai", "model": "fixture", "is_default": false, "rate_per_second": 0, "rate_per_minute": 0]]])
        try api.enqueue(["enabled": false, "bind_fallback": false, "chain": []])
        try api.enqueue(try XCTUnwrap(JSONSerialization.jsonObject(with: LLMWire.encode(LLMRetryPolicy())) as? [String: Any]))
        await store.load()
        XCTAssertEqual(store.profiles.first?.id, "7")
        try api.enqueue(503, [:]); await store.load()
        XCTAssertEqual(store.profiles.first?.id, "7")
        XCTAssertNotNil(store.error)
        XCTAssertTrue(store.hasLoaded)
    }
    @MainActor func testConfirmedSaveStaysSuccessWhenOnlyRefreshFails() async throws {
        let api = LLMFixtureTransport(); let store = LLMStore(service: LLMService(client: api))
        var draft = LLMProfileDraft(); draft.name = "fixture"; draft.model = "fixture"
        try api.enqueue(["id": 7]); try api.enqueue(503, [:])
        let saved = await store.save(draft)
        XCTAssertTrue(saved)
        XCTAssertNotNil(store.notice)
        XCTAssertNotNil(store.error)
        XCTAssertEqual(api.calls.filter { $0.0 == "POST" }.count, 1)
        XCTAssertFalse(store.isMutating)
    }
}
