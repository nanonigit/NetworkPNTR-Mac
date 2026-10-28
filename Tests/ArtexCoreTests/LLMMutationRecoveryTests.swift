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

extension LLMMutationRecoveryTests {
    @MainActor func testEveryMutationFamilyMarksOnlyDispatchedFailuresUncertain() async throws {
        let profile = try LLMWire.decode(LLMProfile.self, from: Data("{\"id\":\"7\",\"name\":\"fixture\",\"format\":\"openai\",\"model\":\"fixture\",\"is_default\":false,\"rate_per_second\":0,\"rate_per_minute\":0}".utf8))
        for kind in 0..<6 {
            let api = LLMHeldTransport(); let store = LLMStore(service: LLMService(client: api))
            api.queue("{}", status: 503)
            switch kind {
            case 0: _ = await store.save(fixture())
            case 1: await store.activate(profile)
            case 2: await store.delete(profile)
            case 3: await store.setRotation(enabled: true)
            case 4: await store.resetPool()
            default: _ = await store.saveRetry(LLMRetryPolicy())
            }
            XCTAssertEqual(api.paths.count, 1, "Family \(kind)")
            XCTAssertNotNil(store.unknownRevision, "Family \(kind)")
            await store.activate(profile); await store.delete(profile); await store.setRotation(enabled: false)
            await store.resetPool(); _ = await store.saveRetry(LLMRetryPolicy()); _ = await store.save(fixture())
            XCTAssertEqual(api.paths.count, 1, "Blocked family \(kind)")
        }
    }
    @MainActor func testEmptyPatchAndInvalidResetAreNotUncertain() async {
        let api = LLMHeldTransport(); let store = LLMStore(service: LLMService(client: api))
        await store.setRotation(); await store.resetPool(id: "7/invalid")
        XCTAssertTrue(api.paths.isEmpty); XCTAssertNil(store.unknownRevision)
        XCTAssertNil(store.noticeKey); XCTAssertFalse(store.isMutating)
    }
    @MainActor func testPreCancelledStoreDoesNotChangeOrDispatch() async {
        let api = LLMHeldTransport(); let store = LLMStore(service: LLMService(client: api)); let draft = fixture()
        let task = Task { @MainActor in
            withUnsafeCurrentTask { $0?.cancel() }
            _ = await store.save(draft); await store.load(); await store.refreshPool()
        }
        await task.value
        XCTAssertTrue(api.paths.isEmpty); XCTAssertNil(store.unknownRevision)
        XCTAssertNil(store.failure); XCTAssertFalse(store.isLoading); XCTAssertFalse(store.isMutating)
    }
    @MainActor func testConfirmedSaveStaysKnownAcrossStopDuringRefresh() async throws {
        let api = LLMHeldTransport(); let store = LLMStore(service: LLMService(client: api))
        api.queue("{\"id\":7}")
        withObservationTracking { _ = store.noticeKey } onChange: {
            MainActor.assumeIsolated { api.hold = true }
        }
        let draft = fixture(); let task = Task { await store.save(draft) }
        await waitForRequest(api); store.stop(); store.resume()
        XCTAssertTrue(store.isMutating); XCTAssertNil(store.unknownRevision)
        api.finish("{}", status: 503)
        let saved = await task.value; XCTAssertTrue(saved)
        XCTAssertNil(store.unknownRevision); XCTAssertNil(store.noticeKey)
        XCTAssertFalse(store.isMutating)
    }
    @MainActor func testReadObservationDeparturePreventsFirstRequest() async {
        let api = LLMHeldTransport(); let store = LLMStore(service: LLMService(client: api))
        withObservationTracking { _ = store.isLoading } onChange: { MainActor.assumeIsolated { store.stop() } }
        await store.load()
        XCTAssertTrue(api.paths.isEmpty); XCTAssertFalse(store.isLoading); XCTAssertFalse(store.hasLoaded)
    }
    @MainActor func testFailedSecondReloadRevokesPreviousReview() async throws {
        let api = LLMHeldTransport(); let store = LLMStore(service: LLMService(client: api))
        api.queue("{}", status: 503); _ = await store.save(fixture())
        let revision = try XCTUnwrap(store.unknownRevision)
        try api.fullLoad(); await store.load(); XCTAssertTrue(store.canAcknowledgeUnknown)
        api.queue("{}", status: 503); await store.load()
        XCTAssertFalse(store.canAcknowledgeUnknown)
        XCTAssertFalse(store.acknowledgeUnknown(revision: revision))
    }
}

extension LLMMutationRecoveryTests {
    @MainActor func testStopIsSafeWhenItsOwnActiveNotificationCallsStopAgain() {
        let api = LLMHeldTransport(); let store = LLMStore(service: LLMService(client: api))
        withObservationTracking { _ = store.isActive } onChange: { MainActor.assumeIsolated { store.stop() } }
        store.stop(); store.stop()
        XCTAssertFalse(store.isActive); XCTAssertFalse(store.isLoading); XCTAssertFalse(store.isMutating)
        store.resume(); XCTAssertTrue(store.isActive); XCTAssertTrue(api.paths.isEmpty)
    }
    @MainActor func testAcknowledgementFromPreviousFailureCannotResumeNewFailure() async throws {
        let api = LLMHeldTransport(); let store = LLMStore(service: LLMService(client: api))
        api.queue("{}", status: 503); _ = await store.save(fixture())
        let first = try XCTUnwrap(store.unknownRevision)
        try api.fullLoad(); await store.load(); XCTAssertTrue(store.acknowledgeUnknown(revision: first))
        api.queue("{}", status: 503); _ = await store.save(fixture())
        let second = try XCTUnwrap(store.unknownRevision); XCTAssertNotEqual(first, second)
        try api.fullLoad(); await store.load()
        XCTAssertFalse(store.acknowledgeUnknown(revision: first))
        XCTAssertTrue(store.acknowledgeUnknown(revision: second))
        XCTAssertEqual(api.methods.filter { $0 != "GET" }.count, 2)
    }
}
