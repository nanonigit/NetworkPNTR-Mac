import XCTest
import Observation
@testable import ArtexCore

@MainActor private final class LLMHeldTransport: BackendJSONTransport {
    var paths: [String] = []
    var methods: [String] = []
    var hold = false
    var pending: CheckedContinuation<BackendHTTPResponse, any Error>?
    var responses: [BackendHTTPResponse] = []
    func queue(_ text: String, status: Int = 200) { responses.append(.init(status: status, body: Data(text.utf8))) }
    func fullLoad() throws {
        queue("{\"profiles\":[]}"); queue("{\"enabled\":false,\"bind_fallback\":false,\"chain\":[]}")
        responses.append(.init(status: 200, body: try LLMWire.encode(LLMRetryPolicy())))
    }
    func send(method: String, path: String, body: Data?, bearer: String?) async throws -> BackendHTTPResponse {
        XCTAssertNil(bearer); paths.append(path); methods.append(method)
        if hold { hold = false; return try await withCheckedThrowingContinuation { pending = $0 } }
        guard !responses.isEmpty else { throw BackendAPIError.invalidResponse }
        return responses.removeFirst()
    }
    func finish(_ text: String = "{}", status: Int = 503) {
        let continuation = pending; pending = nil
        continuation?.resume(returning: .init(status: status, body: Data(text.utf8)))
    }
}

final class LLMMutationRecoveryTests: XCTestCase {
    @MainActor private func fixture() -> LLMProfileDraft {
        var draft = LLMProfileDraft(); draft.name = "fixture 中文 한국어"; draft.model = "fixture"; return draft
    }
    @MainActor private func waitForRequest(_ api: LLMHeldTransport) async {
        for _ in 0..<1000 { if api.pending != nil { return }; await Task.yield() }
        XCTFail("Transport did not receive held request")
    }
    @MainActor func testUncertainWriteRequiresFullReloadAndCurrentExplicitAcknowledgement() async throws {
        let api = LLMHeldTransport(); let store = LLMStore(service: LLMService(client: api))
        api.queue("{}", status: 503)
        let saved = await store.save(fixture()); XCTAssertFalse(saved)
        let revision = try XCTUnwrap(store.unknownRevision)
        XCTAssertFalse(store.canAcknowledgeUnknown)
        XCTAssertFalse(store.acknowledgeUnknown(revision: revision))
        _ = await store.save(fixture()); XCTAssertEqual(api.paths.count, 1)
        api.queue("{\"enabled\":false,\"bind_fallback\":false,\"chain\":[]}")
        await store.refreshPool(); XCTAssertFalse(store.canAcknowledgeUnknown)
        try api.fullLoad(); await store.load()
        XCTAssertEqual(store.unknownRevision, revision); XCTAssertTrue(store.canAcknowledgeUnknown)
        XCTAssertFalse(store.acknowledgeUnknown(revision: UUID()))
        XCTAssertTrue(store.acknowledgeUnknown(revision: revision))
        XCTAssertNil(store.unknownRevision); XCTAssertFalse(store.canAcknowledgeUnknown)
        XCTAssertEqual(api.methods.filter { $0 != "GET" }.count, 1)
    }
    @MainActor func testStopBeforeObservationHandoffSendsNothing() async {
        let api = LLMHeldTransport(); let store = LLMStore(service: LLMService(client: api))
        withObservationTracking { _ = store.isMutating } onChange: {
            MainActor.assumeIsolated { store.stop() }
        }
        let saved = await store.save(fixture())
        XCTAssertFalse(saved); XCTAssertTrue(api.paths.isEmpty); XCTAssertNil(store.unknownRevision)
        XCTAssertFalse(store.isMutating)
    }
    @MainActor func testStopAfterHandoffKeepsGateAndDiscardsLateSuccess() async throws {
        let api = LLMHeldTransport(); let store = LLMStore(service: LLMService(client: api)); api.hold = true
        let draft = fixture(); let write = Task { await store.save(draft) }
        await waitForRequest(api); XCTAssertTrue(store.isMutating)
        store.stop(); store.resume()
        let revision = try XCTUnwrap(store.unknownRevision)
        XCTAssertTrue(store.isMutating); XCTAssertFalse(store.acknowledgeUnknown(revision: revision))
        _ = await store.save(draft); await store.load(); XCTAssertEqual(api.paths.count, 1)
        api.finish("{\"id\":7}", status: 200)
        let saved = await write.value; XCTAssertFalse(saved)
        XCTAssertFalse(store.isMutating); XCTAssertNil(store.noticeKey)
        XCTAssertEqual(store.unknownRevision, revision)
        try api.fullLoad(); await store.load()
        XCTAssertTrue(store.acknowledgeUnknown(revision: revision))
    }
    @MainActor func testCancelledDispatchedWriteIsUncertainButLocalValidationIsNot() async throws {
        let api = LLMHeldTransport(); let store = LLMStore(service: LLMService(client: api))
        var invalid = fixture(); invalid.name = ""
        _ = await store.save(invalid)
        XCTAssertTrue(api.paths.isEmpty); XCTAssertNil(store.unknownRevision)
        api.hold = true; let draft = fixture(); let task = Task { await store.save(draft) }
        await waitForRequest(api); task.cancel(); api.finish("{\"id\":7}", status: 200)
        let saved = await task.value; XCTAssertFalse(saved); XCTAssertNotNil(store.unknownRevision)
        XCTAssertNil(store.noticeKey)
    }
    @MainActor func testOldFullReadCannotContinueOrOverwriteAfterStopResume() async throws {
        let api = LLMHeldTransport(); let store = LLMStore(service: LLMService(client: api)); api.hold = true
        let old = Task { await store.load() }; await waitForRequest(api)
        store.stop(); store.resume(); XCTAssertFalse(store.isLoading)
        try api.fullLoad(); await store.load(); XCTAssertTrue(store.hasLoaded)
        api.finish("{\"profiles\":[{\"id\":\"7\",\"name\":\"obsolete\",\"format\":\"openai\",\"model\":\"fixture\",\"is_default\":false,\"rate_per_second\":0,\"rate_per_minute\":0}]}", status: 200)
        await old.value
        XCTAssertTrue(store.profiles.isEmpty); XCTAssertNil(store.failure)
        XCTAssertEqual(api.paths.count, 4); XCTAssertFalse(store.isLoading)
    }
    @MainActor func testFailedReloadDoesNotPermitAcknowledgement() async throws {
        let api = LLMHeldTransport(); let store = LLMStore(service: LLMService(client: api))
        api.queue("{}", status: 503); _ = await store.save(fixture())
        let revision = try XCTUnwrap(store.unknownRevision)
        api.queue("{\"profiles\":[]}"); api.queue("{}", status: 503)
        await store.load(); XCTAssertFalse(store.canAcknowledgeUnknown)
        XCTAssertFalse(store.acknowledgeUnknown(revision: revision))
    }
}
