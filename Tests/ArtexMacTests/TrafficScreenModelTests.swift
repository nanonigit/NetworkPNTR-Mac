import ArtexCore
import Foundation
import Observation
import XCTest
@testable import ArtexMac

@MainActor private final class TrafficScreenClock {
    struct Wait { let duration: Duration; let continuation: CheckedContinuation<Void, any Error> }
    var waits: [Wait] = []
    func sleep(_ duration: Duration) async throws {
        try await withCheckedThrowingContinuation { waits.append(.init(duration: duration, continuation: $0)) }
    }
    func tick(_ duration: Duration) {
        guard let index = waits.firstIndex(where: { $0.duration == duration }) else { return XCTFail("Missing clock wait") }
        waits.remove(at: index).continuation.resume()
    }
    func releaseAll() { let old = waits; waits = []; for wait in old { wait.continuation.resume(throwing: CancellationError()) } }
}

@MainActor private final class TrafficScreenAPI: BackendJSONTransport {
    var paths: [String] = [], methods: [String] = []
    var holdPage = false, failWrite = false
    var held: [CheckedContinuation<BackendHTTPResponse, any Error>] = []
    func response(_ object: Any, status: Int = 200) throws -> BackendHTTPResponse {
        .init(status: status, body: try JSONSerialization.data(withJSONObject: object))
    }
    func page(_ number: Int64 = 0, size: Int = 50) throws -> BackendHTTPResponse {
        try response(["enabled": true, "count": 200, "total": 200, "page": number, "size": size, "exchanges": [["id": "flow", "ts": "raw", "host": "fixture", "method": "GET", "url": "http://fixture.invalid/", "content_type": "text/plain", "status": 200, "resp_len": 1]]])
    }
    func send(method: String, path: String, body: Data?, bearer: String?) async throws -> BackendHTTPResponse {
        paths.append(path); methods.append(method); XCTAssertNil(bearer)
        if method != "GET" { return try response(["deleted": 1, "reclaimed": 0], status: failWrite ? 500 : 200) }
        if path == "/api/traffic/hosts" { return try response(["hosts": [["host": "fixture", "count": 200]]]) }
        if path == "/api/settings" { return try response(["traffic_capture": true]) }
        if holdPage { return try await withCheckedThrowingContinuation { held.append($0) } }
        let items = URLComponents(string: path)?.queryItems ?? []
        return try page(Int64(items.first { $0.name == "page" }?.value ?? "0") ?? 0, size: Int(items.first { $0.name == "size" }?.value ?? "50") ?? 50)
    }
}

@MainActor final class TrafficScreenModelTests: XCTestCase {
    private func reached(_ predicate: () -> Bool) async throws {
        for _ in 0..<10000 { if predicate() { return }; await Task.yield() }
        XCTFail("Missing controlled handoff"); throw CancellationError()
    }
    private func fixture() async throws -> (TrafficScreenModel, TrafficScreenAPI, TrafficScreenClock, UUID) {
        let api = TrafficScreenAPI(), clock = TrafficScreenClock()
        let model = TrafficScreenModel(store: TrafficStore(service: .init(client: api)), sleep: clock.sleep)
        let lease = try XCTUnwrap(model.begin())
        try await reached { api.paths.count == 3 && !model.store.isRefreshing && clock.waits.count == 1 }
        return (model, api, clock, lease)
    }
    func testIndependentDebouncesMergeCurrentQueryAcrossStoreOwnerRotation() async throws {
        let (model, api, clock, lease) = try await fixture()
        defer { model.stop(lease); clock.releaseAll() }
        XCTAssertTrue(model.edit(.host, text: " host ", lease: lease))
        try await reached { clock.waits.count == 2 }
        XCTAssertTrue(model.edit(.body, text: "body", lease: lease))
        try await reached { clock.waits.count == 3 }
        let old = model.store.owner
        clock.tick(.milliseconds(300))
        try await reached { model.store.query.host == "host" && !model.store.isRefreshing }
        XCTAssertNotEqual(model.store.owner, old); XCTAssertEqual(model.store.query.body, "")
        clock.tick(.milliseconds(300))
        try await reached { model.store.query.body == "body" && !model.store.isRefreshing }
        XCTAssertEqual(model.store.query.host, "host"); XCTAssertFalse(model.hasPendingText)
        XCTAssertEqual(api.methods.filter { $0 != "GET" }.count, 0)
    }
    func testStaleTimerAndOldPresentationSettersCannotRestoreDrafts() async throws {
        let (model, _, clock, lease) = try await fixture()
        XCTAssertTrue(model.edit(.host, text: "private", lease: lease))
        try await reached { clock.waits.count == 2 }
        let next = try XCTUnwrap(model.begin())
        defer { model.stop(next); clock.releaseAll() }
        XCTAssertFalse(model.stop(lease)); XCTAssertFalse(model.edit(.host, text: "retired", lease: lease))
        XCTAssertEqual(model.text(.host, lease: lease), "")
        clock.tick(.milliseconds(300)); await Task.yield()
        XCTAssertEqual(model.store.query.host, ""); XCTAssertEqual(model.text(.host, lease: next), "")
    }
    func testImmediateControlsDoNotFlushPendingTextAndDuplicateEditDoesNotRestartTimer() async throws {
        let (model, _, clock, lease) = try await fixture()
        defer { model.stop(lease); clock.releaseAll() }
        XCTAssertTrue(model.edit(.keyword, text: "later", lease: lease))
        try await reached { clock.waits.count == 2 }
        XCTAssertTrue(model.edit(.keyword, text: "later", lease: lease)); await Task.yield()
        XCTAssertEqual(clock.waits.count, 2)
        XCTAssertTrue(model.control(.method(.post), lease: lease))
        XCTAssertEqual(model.store.query.method, .post); XCTAssertEqual(model.store.query.keyword, "")
        clock.tick(.milliseconds(300))
        try await reached { model.store.query.keyword == "later" }
        XCTAssertEqual(model.store.query.method, .post)
    }
    func testInvalidDraftStaysUnappliedAndCanBeReplaced() async throws {
        let (model, _, clock, lease) = try await fixture()
        defer { model.stop(lease); clock.releaseAll() }
        XCTAssertTrue(model.edit(.path, text: String(repeating: "x", count: 9000), lease: lease))
        try await reached { clock.waits.count == 2 }; clock.tick(.milliseconds(300))
        try await reached { model.store.failure != nil }
        XCTAssertEqual(model.store.query.path, ""); XCTAssertTrue(model.hasPendingText)
        XCTAssertTrue(model.edit(.path, text: "/valid", lease: lease))
        try await reached { clock.waits.contains { $0.duration == .milliseconds(300) } }; clock.tick(.milliseconds(300))
        try await reached { model.store.query.path == "/valid" }
        XCTAssertFalse(model.hasPendingText)
    }
    func testAdvancedResetCancelsAdvancedButRetainsHostTimer() async throws {
        let (model, _, clock, lease) = try await fixture()
        defer { model.stop(lease); clock.releaseAll() }
        XCTAssertTrue(model.edit(.body, text: "retired", lease: lease)); XCTAssertTrue(model.edit(.host, text: "kept", lease: lease))
        try await reached { clock.waits.count == 3 }
        XCTAssertTrue(model.resetAdvanced(lease: lease)); XCTAssertEqual(model.text(.body, lease: lease), "")
        clock.tick(.milliseconds(300)); clock.tick(.milliseconds(300))
        try await reached { model.store.query.host == "kept" }
        XCTAssertEqual(model.store.query.body, "")
    }
    func testPollingOnlyRefreshesPageZeroWhileManualRefreshWorksOnHistory() async throws {
        let (model, api, clock, lease) = try await fixture()
        defer { model.stop(lease); clock.releaseAll() }
        clock.tick(.seconds(5)); try await reached { api.paths.count == 6 && !model.store.isRefreshing }
        XCTAssertTrue(model.page(1, lease: lease)); try await reached { api.paths.count == 9 && !model.store.isRefreshing }
        let count = api.paths.count
        try await reached { clock.waits.contains { $0.duration == .seconds(5) } }; clock.tick(.seconds(5))
        try await reached { clock.waits.contains { $0.duration == .seconds(5) } }
        XCTAssertEqual(api.paths.count, count); XCTAssertEqual(model.store.query.page, 1)
        XCTAssertTrue(model.refresh(lease: lease)); try await reached { api.paths.count == count + 3 && !model.store.isRefreshing }
        XCTAssertEqual(model.store.query.page, 1); XCTAssertFalse(model.page(2, lease: lease))
        XCTAssertTrue(model.page(-1, lease: lease)); try await reached { model.store.query.page == 0 && !model.store.isRefreshing }
        XCTAssertFalse(model.page(-1, lease: lease))
    }
    func testAppliedNoOpKeepsHistoryWithoutRefetch() async throws {
        let (model, api, clock, lease) = try await fixture()
        defer { model.stop(lease); clock.releaseAll() }
        XCTAssertTrue(model.page(1, lease: lease)); try await reached { !model.store.isRefreshing && api.paths.count == 6 }
        XCTAssertTrue(model.edit(.host, text: " \u{FEFF} ", lease: lease))
        try await reached { clock.waits.count == 2 }; clock.tick(.milliseconds(300))
        for _ in 0..<20 { await Task.yield() }
        XCTAssertEqual(model.store.query.page, 1); XCTAssertEqual(api.paths.count, 6); XCTAssertFalse(model.hasPendingText)
    }
    func testHeldOldReadDoesNotBlockNewQueryOrResurrectAfterStop() async throws {
        let (model, api, clock, lease) = try await fixture()
        api.holdPage = true; XCTAssertTrue(model.refresh(lease: lease)); try await reached { api.held.count == 1 }
        XCTAssertFalse(model.refresh(lease: lease))
        api.holdPage = false; XCTAssertTrue(model.control(.method(.post), lease: lease))
        try await reached { model.store.catalog.value != nil && !model.store.catalog.isStale && !model.store.isRefreshing }
        XCTAssertEqual(model.store.query.method, .post)
        XCTAssertTrue(model.stop(lease)); clock.releaseAll()
        api.held.removeFirst().resume(returning: try api.page())
        for _ in 0..<20 { await Task.yield() }
        XCTAssertNil(model.presentation); XCTAssertNil(model.store.catalog.value); XCTAssertFalse(model.store.isActive)
    }
    func testModalBlocksInputsAndPollWithoutIssuingWrites() async throws {
        let (model, api, clock, lease) = try await fixture()
        defer { model.stop(lease); clock.releaseAll() }
        XCTAssertTrue(model.store.prepare(.purgeAll, owner: model.store.owner))
        XCTAssertFalse(model.edit(.host, text: "blocked", lease: lease)); XCTAssertFalse(model.control(.size(25), lease: lease))
        XCTAssertFalse(model.resetAdvanced(lease: lease)); XCTAssertFalse(model.page(1, lease: lease)); XCTAssertFalse(model.refresh(lease: lease))
        let count = api.paths.count; clock.tick(.seconds(5))
        try await reached { clock.waits.contains { $0.duration == .seconds(5) } }
        XCTAssertEqual(api.paths.count, count); XCTAssertTrue(api.methods.allSatisfy { $0 == "GET" })
    }
    func testUnknownOutcomeSurvivesReopenAndReadsNeverAcknowledgeOrRetry() async throws {
        let (model, api, clock, lease) = try await fixture()
        api.failWrite = true; XCTAssertTrue(model.store.prepare(.purgeAll, owner: model.store.owner))
        let dialog = try XCTUnwrap(model.store.confirmation)
        guard case .unconfirmed = await model.store.confirm(id: dialog.id, owner: dialog.owner) else { return XCTFail("Expected unknown") }
        XCTAssertTrue(model.stop(lease)); let next = try XCTUnwrap(model.begin())
        defer { model.stop(next); clock.releaseAll() }
        try await reached { model.store.canAcknowledgeUnknown }
        let revision = model.store.unknownRevision
        XCTAssertTrue(model.store.hasUnknownOutcome); XCTAssertEqual(api.methods.filter { $0 == "DELETE" }.count, 1)
        model.reset(); clock.releaseAll()
        XCTAssertNil(model.presentation); XCTAssertNil(model.store.unknownChange)
        XCTAssertTrue(model.store.hasUnknownOutcome); XCTAssertEqual(model.store.unknownRevision, revision)
    }
    func testStopDuringDraftPublicationScrubsAndDoesNotScheduleTimer() async throws {
        let (model, _, clock, lease) = try await fixture()
        withObservationTracking { _ = model.drafts } onChange: { MainActor.assumeIsolated { _ = model.stop(lease) } }
        XCTAssertFalse(model.edit(.host, text: "private", lease: lease))
        XCTAssertNil(model.presentation); XCTAssertEqual(model.text(.host, lease: lease), "")
        XCTAssertFalse(model.store.isActive); clock.releaseAll()
    }
    func testResetDuringQueryPublicationCannotAdoptPrivateDraftOrRestart() async throws {
        let (model, _, clock, lease) = try await fixture()
        XCTAssertTrue(model.edit(.host, text: "private", lease: lease))
        try await reached { clock.waits.count == 2 }
        withObservationTracking { _ = model.store.query } onChange: {
            MainActor.assumeIsolated { model.reset(); XCTAssertNil(model.begin()) }
        }
        clock.tick(.milliseconds(300)); try await reached { model.presentation == nil }
        XCTAssertEqual(model.store.query.host, ""); XCTAssertEqual(model.text(.host, lease: lease), "")
        XCTAssertFalse(model.store.isActive); clock.releaseAll()
    }
    func testMaturedDraftWaitsForConfirmationClose() async throws {
        let (model, _, clock, lease) = try await fixture()
        defer { model.stop(lease); clock.releaseAll() }
        XCTAssertTrue(model.edit(.host, text: "delayed", lease: lease))
        try await reached { clock.waits.count == 2 }
        XCTAssertTrue(model.store.prepare(.purgeAll, owner: model.store.owner))
        let dialog = try XCTUnwrap(model.store.confirmation)
        clock.tick(.milliseconds(300))
        for _ in 0..<20 { await Task.yield() }
        XCTAssertEqual(model.store.query.host, ""); XCTAssertTrue(model.hasPendingText)
        XCTAssertTrue(model.store.cancelConfirmation(id: dialog.id, owner: dialog.owner))
        try await reached { model.store.query.host == "delayed" }
        XCTAssertFalse(model.hasPendingText)
    }
    func testResetRequestedDuringStopScrubsUnknownScope() async throws {
        let (model, api, clock, lease) = try await fixture()
        defer { model.reset(); clock.releaseAll() }
        api.failWrite = true
        XCTAssertTrue(model.store.prepare(.purgeAll, owner: model.store.owner))
        let dialog = try XCTUnwrap(model.store.confirmation)
        guard case .unconfirmed = await model.store.confirm(id: dialog.id, owner: dialog.owner) else { return XCTFail("Expected unknown") }
        withObservationTracking { _ = model.store.isActive } onChange: { MainActor.assumeIsolated { model.reset() } }
        XCTAssertTrue(model.stop(lease))
        XCTAssertTrue(model.store.hasUnknownOutcome); XCTAssertNil(model.store.unknownChange)
    }
    func testResetDuringBeginRetirementPreventsReopening() async throws {
        let (model, _, clock, _) = try await fixture()
        defer { model.reset(); clock.releaseAll() }
        withObservationTracking { _ = model.store.isActive } onChange: { MainActor.assumeIsolated { model.reset() } }
        XCTAssertNil(model.begin()); XCTAssertNil(model.presentation); XCTAssertFalse(model.store.isActive)
    }

}
