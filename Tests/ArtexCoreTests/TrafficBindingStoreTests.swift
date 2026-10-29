import Foundation
import Observation
import XCTest
@testable import ArtexCore

private struct TrafficBindingBody: Decodable { let trafficRefs: [TrafficBindingReference] }
private struct TrafficBindingReference: Decodable { let trafficId, role, note: String }

@MainActor private final class TrafficBindingAPI: BackendJSONTransport {
    struct Call { let method, path: String; let body: Data? }
    var calls: [Call] = []
    var ids: [String] = [], version: Int64 = 2
    var failRead = false, failWrite = false, holdRead = false, holdWrite = false, omitLast = false
    var advanceVersion = true, normalizeRefs = false
    var pendingReads: [CheckedContinuation<BackendHTTPResponse, any Error>] = []
    var pendingWrites: [CheckedContinuation<BackendHTTPResponse, any Error>] = []
    var onSend: (@MainActor (String) -> Void)?
    func reply(owner: String = "7", status: Int = 200) throws -> BackendHTTPResponse {
        let bindings: [[String: Any]] = ids.enumerated().map { index, source in
            let snapshot = "snapshot-" + String(index)
            return ["id": String(index + 1), "finding_id": owner, "snapshot_id": snapshot, "role": "supporting", "note": "", "position": index, "created_at": "raw", "snapshot": ["id": snapshot, "source_traffic_id": source, "captured_at": 0, "url": "http://fixture.invalid/", "method": "GET", "content_type": "text/plain", "status": 200, "req_hash": "r", "resp_hash": "s", "req_len": 0, "resp_len": 0]]
        }
        return .init(status: status, body: try JSONSerialization.data(withJSONObject: ["finding_id": owner, "version": version, "report_version": 1, "bindings": bindings]))
    }
    func send(method: String, path: String, body: Data?, bearer: String?) async throws -> BackendHTTPResponse {
        XCTAssertNil(bearer); calls.append(.init(method: method, path: path, body: body)); onSend?(method)
        let owner = String(path.split(separator: "/")[3])
        if method == "GET" {
            if holdRead { return try await withCheckedThrowingContinuation { pendingReads.append($0) } }
            return try reply(owner: owner, status: failRead ? 503 : 200)
        }
        let object = try BackendJSONCoding.decode(TrafficBindingBody.self, from: XCTUnwrap(body))
        ids = object.trafficRefs.map(\.trafficId)
        if normalizeRefs { ids = ids.map { $0.precomposedStringWithCanonicalMapping } }
        if omitLast { ids.removeLast() }; if advanceVersion { version += 1 }
        if holdWrite { return try await withCheckedThrowingContinuation { pendingWrites.append($0) } }
        return try reply(owner: owner, status: failWrite ? 503 : 200)
    }
}

@MainActor private final class TrafficBindingJob { var task: Task<FindingTrafficMutationOutcome, Never>? }

@MainActor final class TrafficBindingStoreTests: XCTestCase {
    private let sources = ["é", "e\u{301}", "\u{FEFF}中文 한국어"]
    private func target(_ id: String = "7", inherited: Bool = false, legacy: Bool = false) throws -> FindingRecord {
        var value: [String: Any] = ["id": "41", "finding_id": id, "task_id": "11", "name": "private name", "vulnclass": "CWE-79", "severity": "high", "status": "pending", "summary": "private", "evidence": "raw", "ts": "raw"]
        if inherited { value["inherited"] = true; value["source_task_id"] = "11" }
        if legacy { value.removeValue(forKey: "finding_id") }
        return try BackendJSONCoding.decode(FindingRecord.self, from: JSONSerialization.data(withJSONObject: value))
    }
    private func ready(_ api: TrafficBindingAPI) async throws -> TrafficBindingStore {
        let store = TrafficBindingStore(service: .init(client: api))
        XCTAssertTrue(store.select(try target(), sourceIDs: sources, owner: store.owner))
        await store.refresh(owner: store.owner); XCTAssertTrue(store.canBind); return store
    }
    private func reached(_ predicate: () -> Bool) async throws {
        for _ in 0..<10000 { if predicate() { return }; await Task.yield() }
        XCTFail("Missing controlled handoff"); throw CancellationError()
    }
    func testCanonicalMutableHandleLiteralRefsAndConsumedRequest() async throws {
        let api = TrafficBindingAPI(), store = try await ready(api), owner = store.owner, request = store.requestID
        XCTAssertEqual(store.sourceIDs.map { Data($0.utf8) }, sources.map { Data($0.utf8) })
        let outcome = await store.bind(id: request, owner: owner)
        XCTAssertEqual(api.ids.map { Data($0.utf8) }, sources.map { Data($0.utf8) })
        guard case .confirmed(let receipt) = outcome else { return XCTFail("Expected verified bind: " + (store.failure?.text(language: .english) ?? "no error")) }
        XCTAssertEqual(receipt.findingId, "7"); XCTAssertEqual(api.calls.map(\.method), ["GET", "POST"])
        XCTAssertTrue(api.calls.allSatisfy { $0.path == "/api/exploration/findings/7/traffic" })
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(api.calls.last?.body)) as? [String: Any])
        let refs = try BackendJSONCoding.decode(TrafficBindingBody.self, from: XCTUnwrap(api.calls.last?.body)).trafficRefs
        XCTAssertEqual(Set(body.keys), ["traffic_refs"])
        XCTAssertEqual(refs.map(\.trafficId).map { Data($0.utf8) }, sources.map { Data($0.utf8) })
        XCTAssertTrue(refs.allSatisfy { $0.role == "supporting" && $0.note == "" })
        guard case .notStarted = await store.bind(id: request, owner: owner) else { return XCTFail("Replay") }
        XCTAssertEqual(api.calls.count, 2)
    }
    func testInvalidTargetsIDsDuplicatesAndBodyLimitHaveNoDispatch() throws {
        let api = TrafficBindingAPI(), store = TrafficBindingStore(service: .init(client: api)), owner = store.owner
        XCTAssertThrowsError(try target("007")); XCTAssertThrowsError(try target("not-a-number"))
        for row in [try target(inherited: true), try target(legacy: true)] {
            XCTAssertFalse(store.select(row, sourceIDs: sources, owner: owner))
        }
        for ids in [[], [""], [" "], ["bad\nID"], ["same", "same"], [String(repeating: "x", count: 8193)], (0..<140).map { String($0) + String(repeating: "x", count: 8180) }] {
            XCTAssertFalse(store.select(try target(), sourceIDs: ids, owner: owner))
        }
        XCTAssertEqual(store.owner, owner); XCTAssertTrue(api.calls.isEmpty); XCTAssertNil(store.target)
    }
    func testFreshReadAndOwnerAreRequiredAndReadFailureRetainsLastGood() async throws {
        let api = TrafficBindingAPI(), store = TrafficBindingStore(service: .init(client: api))
        XCTAssertTrue(store.select(try target(), sourceIDs: sources, owner: store.owner))
        guard case .notStarted = await store.bind(id: store.requestID, owner: store.owner) else { return XCTFail("Missing summary") }
        let old = store.owner; await store.refresh(owner: old); XCTAssertTrue(store.canBind)
        api.failRead = true; await store.refresh(owner: old)
        XCTAssertNotNil(store.summary); XCTAssertTrue(store.isStale); XCTAssertFalse(store.canBind)
        api.failRead = false; await store.refresh(owner: old)
        XCTAssertTrue(store.select(try target("8"), sourceIDs: sources, owner: old))
        let count = api.calls.count; await store.refresh(owner: old)
        XCTAssertEqual(api.calls.count, count); XCTAssertFalse(store.stop(ifOwnedBy: old)); XCTAssertTrue(store.isActive)
    }
    func testMissingReceiptSourceNeverConfirms() async throws {
        let api = TrafficBindingAPI(), store = try await ready(api); api.omitLast = true
        guard case .unconfirmed = await store.bind(id: store.requestID, owner: store.owner) else { return XCTFail("Incomplete receipt") }
        XCTAssertTrue(store.hasUnknownOutcome); XCTAssertNil(store.lastConfirmation); XCTAssertFalse(store.canBind)
    }
    func testExplicitFreshRecoveryAndAckRotateRequestWithoutReplay() async throws {
        let api = TrafficBindingAPI(), store = try await ready(api); api.failWrite = true
        let owner = store.owner, request = store.requestID
        guard case .unconfirmed = await store.bind(id: request, owner: owner) else { return XCTFail("Expected unknown") }
        let revision = store.unknownRevision
        XCTAssertFalse(store.acknowledge(owner: owner, revision: revision))
        XCTAssertFalse(store.select(try target("8"), sourceIDs: sources, owner: owner))
        await store.recover(owner: owner)
        XCTAssertTrue(store.canAcknowledgeUnknown); XCTAssertTrue(store.hasUnknownOutcome)
        XCTAssertFalse(store.acknowledge(owner: UUID(), revision: revision)); XCTAssertFalse(store.acknowledge(owner: owner, revision: UUID()))
        XCTAssertTrue(store.acknowledge(owner: owner, revision: revision)); XCTAssertNotEqual(store.requestID, request)
        guard case .notStarted = await store.bind(id: request, owner: owner) else { return XCTFail("Old request replay") }
        XCTAssertEqual(api.calls.filter { $0.method == "POST" }.count, 1)
    }
    func testRecoveryFailureAndOlderVersionCannotAcknowledge() async throws {
        let api = TrafficBindingAPI(), store = try await ready(api); api.failWrite = true
        _ = await store.bind(id: store.requestID, owner: store.owner)
        api.failRead = true; await store.recover(owner: store.owner); XCTAssertFalse(store.canAcknowledgeUnknown)
        api.failRead = false; api.version = 1; await store.recover(owner: store.owner); XCTAssertFalse(store.canAcknowledgeUnknown)
        api.version = 3; await store.recover(owner: store.owner); XCTAssertTrue(store.canAcknowledgeUnknown)
    }
    func testPredispatchStopRevokesBytesWithoutUnknown() async throws {
        let api = TrafficBindingAPI(), store = try await ready(api), owner = store.owner
        withObservationTracking { _ = store.isMutating } onChange: { MainActor.assumeIsolated { _ = store.stop(ifOwnedBy: owner) } }
        guard case .notStarted = await store.bind(id: store.requestID, owner: owner) else { return XCTFail("Pre-dispatch departure") }
        XCTAssertEqual(api.calls.count, 1); XCTAssertFalse(store.hasUnknownOutcome); XCTAssertFalse(store.isMutating)
        XCTAssertNil(store.target); XCTAssertTrue(store.sourceIDs.isEmpty)
    }
    func testPostdispatchStopKeepsUnknownAndScrubsPublicScope() async throws {
        let api = TrafficBindingAPI(), store = try await ready(api), owner = store.owner
        api.onSend = { if $0 == "POST" { _ = store.stop(ifOwnedBy: owner) } }
        guard case .discarded = await store.bind(id: store.requestID, owner: owner) else { return XCTFail("Retired caller") }
        XCTAssertTrue(store.hasUnknownOutcome); XCTAssertNil(store.target); XCTAssertTrue(store.sourceIDs.isEmpty); XCTAssertNil(store.summary)
        store.resume(); await store.recover(owner: store.owner)
        XCTAssertTrue(store.canAcknowledgeUnknown); XCTAssertNil(store.target); XCTAssertEqual(store.summary?.findingId, "7")
    }
    func testHeldWriteSurvivesResetUntilSettlementAndRecoveryIsExplicit() async throws {
        let api = TrafficBindingAPI(), store = try await ready(api); api.holdWrite = true
        let owner = store.owner, request = store.requestID
        let job = Task { await store.bind(id: request, owner: owner) }
        try await reached { api.pendingWrites.count == 1 }
        store.resetSession(); store.resume(); XCTAssertTrue(store.isMutating); XCTAssertTrue(store.hasUnknownOutcome)
        XCTAssertNil(store.target); XCTAssertTrue(store.sourceIDs.isEmpty); XCTAssertNil(store.summary)
        let count = api.calls.count; await store.recover(owner: store.owner); XCTAssertEqual(api.calls.count, count)
        XCTAssertFalse(store.select(try target(), sourceIDs: sources, owner: store.owner))
        api.pendingWrites.removeFirst().resume(returning: try api.reply())
        guard case .discarded = await job.value else { return XCTFail("Late writer") }
        XCTAssertFalse(store.isMutating); XCTAssertNil(store.lastConfirmation); XCTAssertTrue(store.hasUnknownOutcome)
        await store.recover(owner: store.owner); XCTAssertTrue(store.canAcknowledgeUnknown)
        XCTAssertEqual(api.calls.filter { $0.method == "POST" }.count, 1)
    }
    func testCancelledCallerAfterDispatchRetainsUnknownWithoutErrorOrRetry() async throws {
        let api = TrafficBindingAPI(), store = try await ready(api); api.holdWrite = true
        let owner = store.owner, request = store.requestID
        let job = Task { await store.bind(id: request, owner: owner) }; try await reached { api.pendingWrites.count == 1 }
        job.cancel(); api.pendingWrites.removeFirst().resume(returning: try api.reply())
        guard case .discarded = await job.value else { return XCTFail("Cancelled caller") }
        XCTAssertTrue(store.hasUnknownOutcome); XCTAssertNil(store.failure); XCTAssertFalse(store.isMutating)
    }
    func testLateReadAfterNewSelectionCannotPublishOldSummary() async throws {
        let api = TrafficBindingAPI(), store = try await ready(api); api.holdRead = true
        let owner = store.owner, job = Task { await store.refresh(owner: owner) }
        try await reached { api.pendingReads.count == 1 }
        XCTAssertTrue(store.select(try target("8"), sourceIDs: ["new"], owner: owner)); api.holdRead = false
        await store.refresh(owner: store.owner); XCTAssertEqual(store.summary?.findingId, "8")
        api.pendingReads.removeFirst().resume(returning: try api.reply(owner: "7")); await job.value
        XCTAssertEqual(store.summary?.findingId, "8")
    }
    func testStopDuringSummaryPublicationCannotResurrectData() async throws {
        let api = TrafficBindingAPI(), store = try await ready(api), owner = store.owner
        withObservationTracking { _ = store.summary } onChange: { MainActor.assumeIsolated { _ = store.stop(ifOwnedBy: owner) } }
        await store.refresh(owner: owner)
        XCTAssertNil(store.summary); XCTAssertNil(store.target); XCTAssertFalse(store.isActive); XCTAssertFalse(store.isLoading)
    }
    func testReceiptPublicationResetKeepsOnlyGenericUncertainty() async throws {
        let api = TrafficBindingAPI(), store = try await ready(api)
        api.onSend = { method in
            if method == "POST" { withObservationTracking { _ = store.summary } onChange: { MainActor.assumeIsolated { store.resetSession(); store.resume() } } }
        }
        guard case .discarded = await store.bind(id: store.requestID, owner: store.owner) else { return XCTFail("Receipt departure") }
        XCTAssertNil(store.summary); XCTAssertNil(store.lastConfirmation); XCTAssertNil(store.target); XCTAssertTrue(store.sourceIDs.isEmpty)
        XCTAssertTrue(store.hasUnknownOutcome); XCTAssertFalse(store.isActive)
    }
    func testBusyReleaseDepartureDiscardsKnownReceiptWithoutInventingUnknown() async throws {
        let api = TrafficBindingAPI(), store = try await ready(api)
        api.onSend = { method in
            if method == "POST" { withObservationTracking { _ = store.isMutating } onChange: { MainActor.assumeIsolated { _ = store.stop() } } }
        }
        guard case .discarded = await store.bind(id: store.requestID, owner: store.owner) else { return XCTFail("Busy-release departure") }
        XCTAssertNil(store.lastConfirmation); XCTAssertFalse(store.hasUnknownOutcome); XCTAssertFalse(store.isMutating)
    }
    func testFixtureReceiptRoundTripPreservesLiteralSources() throws {
        let api = TrafficBindingAPI(); api.ids = sources
        let value = try BackendJSONCoding.decode(FindingTraffic.self, from: api.reply().body)
        XCTAssertEqual(value.bindings.map { Data($0.snapshot.sourceTrafficId.utf8) }, sources.map { Data($0.utf8) })
    }

    func testCancellationDuringBusyPublicationHasNoDispatchOrUncertainty() async throws {
        let api = TrafficBindingAPI(), store = try await ready(api), holder = TrafficBindingJob()
        let owner = store.owner, request = store.requestID
        withObservationTracking { _ = store.isMutating } onChange: { MainActor.assumeIsolated { holder.task?.cancel() } }
        holder.task = Task { await store.bind(id: request, owner: owner) }
        guard case .notStarted = await holder.task!.value else { return XCTFail("Cancelled before dispatch") }
        XCTAssertEqual(api.calls.count, 1); XCTAssertFalse(store.hasUnknownOutcome); XCTAssertFalse(store.isMutating)
    }
    func testOldAckCannotClearASecondUncertaintyEpisode() async throws {
        let api = TrafficBindingAPI(), store = try await ready(api); api.failWrite = true
        let owner = store.owner, oldRequest = store.requestID
        _ = await store.bind(id: oldRequest, owner: owner)
        let oldRevision = store.unknownRevision
        await store.recover(owner: owner); XCTAssertTrue(store.acknowledge(owner: owner, revision: oldRevision))
        _ = await store.bind(id: store.requestID, owner: owner)
        let nextRevision = store.unknownRevision; XCTAssertNotEqual(nextRevision, oldRevision)
        await store.recover(owner: owner); XCTAssertTrue(store.canAcknowledgeUnknown)
        XCTAssertFalse(store.acknowledge(owner: owner, revision: oldRevision)); XCTAssertTrue(store.hasUnknownOutcome)
        XCTAssertTrue(store.acknowledge(owner: owner, revision: nextRevision))
        guard case .notStarted = await store.bind(id: oldRequest, owner: owner) else { return XCTFail("Old request") }
        XCTAssertEqual(api.calls.filter { $0.method == "POST" }.count, 2)
    }
    func testAlreadyBoundSourcesAllowIdempotentUnchangedVersion() async throws {
        let api = TrafficBindingAPI(); api.ids = sources; api.advanceVersion = false
        let store = try await ready(api)
        guard case .confirmed(let value) = await store.bind(id: store.requestID, owner: store.owner) else { return XCTFail("Idempotent receipt") }
        XCTAssertEqual(value.version, 2); XCTAssertFalse(store.hasUnknownOutcome); XCTAssertFalse(store.canBind)
    }
    func testNormalizationOfReceiptSourcesCannotSilentlyConfirm() async throws {
        let api = TrafficBindingAPI(), store = try await ready(api); api.normalizeRefs = true
        guard case .unconfirmed = await store.bind(id: store.requestID, owner: store.owner) else { return XCTFail("Changed literal identities") }
        XCTAssertTrue(store.hasUnknownOutcome); XCTAssertNil(store.lastConfirmation)
    }
    func testLateRecoveryCannotReplaceFreshPostResetProof() async throws {
        let api = TrafficBindingAPI(), store = try await ready(api); api.failWrite = true
        _ = await store.bind(id: store.requestID, owner: store.owner)
        api.holdRead = true
        let owner = store.owner, read = Task { await store.recover(owner: owner) }
        try await reached { api.pendingReads.count == 1 }
        store.resetSession(); store.resume(); api.holdRead = false
        await store.recover(owner: store.owner); XCTAssertTrue(store.canAcknowledgeUnknown)
        api.version = 1; api.pendingReads.removeFirst().resume(returning: try api.reply())
        await read.value
        XCTAssertEqual(store.summary?.version, 3); XCTAssertFalse(store.isStale); XCTAssertNil(store.failure)
        XCTAssertTrue(store.canAcknowledgeUnknown); XCTAssertNil(store.target); XCTAssertTrue(store.sourceIDs.isEmpty)
    }

}
