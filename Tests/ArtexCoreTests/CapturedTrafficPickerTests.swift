import XCTest
import Observation
@testable import ArtexCore

@MainActor private final class PickerTrafficAPI: BackendJSONTransport {
    struct Call { let method, path: String; let body: Data? }
    var calls: [Call] = []
    var queued: [BackendHTTPResponse] = []
    var held: [Int: CheckedContinuation<BackendHTTPResponse, any Error>] = [:]
    func enqueue(_ value: [String: Any], status: Int = 200) throws { queued.append(.init(status: status, body: try JSONSerialization.data(withJSONObject: value))) }
    func send(method: String, path: String, body: Data?, bearer: String?) async throws -> BackendHTTPResponse {
        XCTAssertNil(bearer); let index = calls.count; calls.append(.init(method: method, path: path, body: body))
        if !queued.isEmpty { return queued.removeFirst() }
        return try await withCheckedThrowingContinuation { held[index] = $0 }
    }
    func reply(_ index: Int, _ value: [String: Any], status: Int = 200) throws {
        let continuation = try XCTUnwrap(held.removeValue(forKey: index))
        continuation.resume(returning: .init(status: status, body: try JSONSerialization.data(withJSONObject: value)))
    }
}

@MainActor final class CapturedTrafficPickerTests: XCTestCase {
    private func target(inherited: Bool = false, legacy: Bool = false) throws -> FindingRecord {
        var row: [String: Any] = ["id": "9101", "finding_id": "9101", "task_id": "8101", "vulnclass": "CWE-79", "severity": "high", "status": "pending", "summary": "", "evidence": "", "ts": "raw"]
        if inherited { row["inherited"] = true; row["source_task_id"] = "8101" }
        if legacy { row.removeValue(forKey: "finding_id") }
        return try BackendJSONCoding.decode(FindingRecord.self, from: JSONSerialization.data(withJSONObject: row))
    }
    private func summary(version: Int = 2, sources: [String] = ["bound"]) throws -> [String: Any] {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "Fixtures/findings-traffic-contract", withExtension: "json"))
        let fixture = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let original = try XCTUnwrap(fixture["binding"] as? [String: Any])
        let bindings = try sources.enumerated().map { index, source -> [String: Any] in
            var row = original; row["id"] = String(index + 1); row["finding_id"] = "9101"; row["position"] = index
            var snapshot = try XCTUnwrap(row["snapshot"] as? [String: Any]); snapshot["source_traffic_id"] = source; row["snapshot"] = snapshot
            return row
        }
        return ["finding_id": "9101", "version": version, "report_version": 1, "bindings": bindings]
    }
    private func catalog(_ ids: [String], page: Int = 0, total: Int = 30) -> [String: Any] {
        ["enabled": true, "count": total, "total": total, "page": page, "size": 25, "exchanges": ids.map { ["id": $0, "ts": "raw", "host": "fixture", "method": "GET", "url": "https://captured.invalid", "status": 200, "content_type": "text/plain", "resp_len": 1] }]
    }
    private func make(inherited: Bool = false, legacy: Bool = false) async throws -> (PickerTrafficAPI, FindingTrafficStore, CapturedTrafficPickerStore) {
        let api = PickerTrafficAPI(); let evidence = FindingTrafficStore(service: .init(client: api))
        XCTAssertTrue(evidence.select(try target(inherited: inherited, legacy: legacy)))
        if !legacy { try api.enqueue(summary()); await evidence.refreshSummary() }
        return (api, evidence, CapturedTrafficPickerStore(service: .init(client: api), evidence: evidence))
    }
    private func loaded(_ picker: CapturedTrafficPickerStore, _ api: PickerTrafficAPI, _ ids: [String] = ["bound", "é", "e\u{301}"]) async throws {
        try api.enqueue(catalog(ids, page: Int(picker.query.page))); await picker.refreshCatalog()
    }
    private func reached(_ condition: () -> Bool) async throws {
        for _ in 0..<2000 { if condition() { return }; try await Task.sleep(for: .milliseconds(1)) }
        XCTFail("Picker did not reach the expected phase"); throw BackendAPIError.invalidResponse
    }
    func testCrossPageSelectionUsesByteIDsAndExcludesBoundRows() async throws {
        let (api, _, picker) = try await make(); try await loaded(picker, api)
        let old = picker.owner
        XCTAssertFalse(picker.toggle(id: "bound", selected: true, owner: old))
        XCTAssertTrue(picker.selectPage(true, owner: old)); XCTAssertEqual(picker.selectedIDs.map { Data($0.utf8) }, [Data("é".utf8), Data("e\u{301}".utf8)])
        XCTAssertTrue(picker.nextPage(owner: old)); XCTAssertFalse(picker.toggle(id: "é", selected: false, owner: old))
        try await loaded(picker, api, ["other"])
        XCTAssertTrue(picker.toggle(id: "other", selected: true, owner: picker.owner)); XCTAssertEqual(picker.selectedCount, 3)
        XCTAssertTrue(picker.previousPage(owner: picker.owner)); try await loaded(picker, api)
        XCTAssertTrue(picker.selectPage(false, owner: picker.owner)); XCTAssertEqual(picker.selectedIDs, ["other"])
        XCTAssertTrue(picker.clearSelection(owner: picker.owner)); XCTAssertTrue(picker.selectedIDs.isEmpty)
        XCTAssertTrue(api.calls.allSatisfy { $0.method == "GET" })
    }
    func testFailedReloadKeepsStaleDataButCannotSelectItAndFiltersKeepSelection() async throws {
        let (api, _, picker) = try await make(); try await loaded(picker, api)
        XCTAssertTrue(picker.toggle(id: "é", selected: true, owner: picker.owner))
        try api.enqueue([:], status: 503); await picker.refreshCatalog()
        XCTAssertNotNil(picker.catalog.value); XCTAssertTrue(picker.catalog.isStale)
        XCTAssertFalse(picker.toggle(id: "e\u{301}", selected: true, owner: picker.owner))
        var query = picker.query; query.host = "\u{feff}e\u{301} 中文 한국어"
        XCTAssertTrue(picker.configure(query, owner: picker.owner)); XCTAssertNil(picker.catalog.value)
        XCTAssertEqual(picker.selectedCount, 1); XCTAssertEqual(Data(picker.query.host.utf8), Data(query.host.utf8))
        query.page = -1; XCTAssertFalse(picker.configure(query, owner: picker.owner)); XCTAssertNotNil(picker.failure)
    }
    func testReverseCatalogRepliesAndParentSelectionCannotReviveOldOwner() async throws {
        let (api, evidence, picker) = try await make(); let base = api.calls.count
        let old = Task { await picker.refreshCatalog() }; try await reached { api.held[base] != nil }
        var query = picker.query; query.keyword = "new"
        XCTAssertTrue(picker.configure(query, owner: picker.owner))
        let current = Task { await picker.refreshCatalog() }; try await reached { api.held[base + 1] != nil }
        try api.reply(base + 1, catalog(["new"])); await current.value
        try api.reply(base, catalog(["old"])); await old.value
        XCTAssertEqual(picker.catalog.value?.exchanges.first?.id, "new")
        XCTAssertTrue(evidence.select(try target())); let count = api.calls.count
        await picker.refreshCatalog(); XCTAssertFalse(picker.isCurrent); XCTAssertEqual(api.calls.count, count)
        XCTAssertFalse(picker.toggle(id: "new", selected: true, owner: picker.owner))
    }
    func testReversePreviewRepliesKeepExactSelectedIdentity() async throws {
        let (api, _, picker) = try await make(); try await loaded(picker, api); let base = api.calls.count
        XCTAssertTrue(picker.selectPreview(id: "é", owner: picker.owner))
        let old = Task { await picker.refreshPreview() }; try await reached { api.held[base] != nil }
        XCTAssertTrue(picker.selectPreview(id: "e\u{301}", owner: picker.owner))
        let current = Task { await picker.refreshPreview() }; try await reached { api.held[base + 1] != nil }
        try api.reply(base + 1, ["req": "\u{feff}e\u{301} 中文 한국어", "resp": "new"]); await current.value
        try api.reply(base, ["req": "old", "resp": "old"]); await old.value
        XCTAssertEqual(picker.selectedPreviewID.map { Data($0.utf8) }, Data("e\u{301}".utf8))
        XCTAssertEqual(picker.preview.value?.response, "new")
        XCTAssertTrue(picker.selectPreview(id: nil, owner: picker.owner)); XCTAssertNil(picker.preview.value)
    }
    func testConfirmedBindUsesSelectedOrderAndClearsOnlyCurrentSelection() async throws {
        let (api, evidence, picker) = try await make(); try await loaded(picker, api)
        XCTAssertTrue(picker.selectPage(true, owner: picker.owner)); XCTAssertTrue(picker.canBind)
        try api.enqueue(summary(version: 3, sources: ["bound", "é", "e\u{301}"]))
        guard case .confirmed = await picker.bind(owner: picker.owner) else { return XCTFail("Binding was not confirmed") }
        let call = try XCTUnwrap(api.calls.last); XCTAssertEqual(call.method, "POST")
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(call.body)) as? [String: Any])
        let refs = try XCTUnwrap(object["traffic_refs"] as? [[String: Any]])
        XCTAssertEqual(refs.compactMap { ($0["traffic_id"] as? String).map { Data($0.utf8) } }, [Data("é".utf8), Data("e\u{301}".utf8)])
        XCTAssertTrue(picker.selectedIDs.isEmpty); XCTAssertEqual(evidence.summary.value?.version, 3); XCTAssertFalse(picker.isSubmitting)
    }
    func testConflictBlocksRepeatAndReadsNeverAcknowledgeOrResend() async throws {
        let (api, evidence, picker) = try await make(); try await loaded(picker, api)
        XCTAssertTrue(picker.toggle(id: "é", selected: true, owner: picker.owner))
        try api.enqueue([:], status: 409)
        guard case .unconfirmed = await picker.bind(owner: picker.owner) else { return XCTFail("Conflict must be uncertain") }
        XCTAssertEqual(evidence.unknownIDs, ["9101"]); XCTAssertFalse(picker.canBind); XCTAssertEqual(picker.selectedCount, 1)
        guard case .notStarted = await picker.bind(owner: picker.owner) else { return XCTFail("Unexpected replay") }
        try api.enqueue(summary(version: 4)); await evidence.refreshSummary()
        XCTAssertFalse(picker.canBind); XCTAssertEqual(api.calls.filter { $0.method == "POST" }.count, 1)
        XCTAssertTrue(evidence.acknowledgeUnknown("9101", owner: evidence.owner, revision: evidence.unknownRevision))
        XCTAssertTrue(picker.canBind); XCTAssertEqual(api.calls.filter { $0.method == "POST" }.count, 1)
    }
    func testParentBusyNotificationClosesPickerBeforeHandoffWithoutSending() async throws {
        let (api, evidence, picker) = try await make(); try await loaded(picker, api)
        XCTAssertTrue(picker.toggle(id: "é", selected: true, owner: picker.owner))
        withObservationTracking { _ = evidence.isMutating } onChange: { MainActor.assumeIsolated { picker.stop() } }
        guard case .notStarted = await picker.bind(owner: picker.owner) else { return XCTFail("Closed before handoff") }
        XCTAssertFalse(api.calls.contains { $0.method == "POST" }); XCTAssertTrue(evidence.unknownIDs.isEmpty); XCTAssertFalse(picker.isSubmitting)
    }
    func testChildBusyNotificationDeparturePreventsParentWrite() async throws {
        let (api, evidence, picker) = try await make(); try await loaded(picker, api)
        XCTAssertTrue(picker.toggle(id: "é", selected: true, owner: picker.owner))
        withObservationTracking { _ = picker.isSubmitting } onChange: { MainActor.assumeIsolated { picker.stop() } }
        guard case .notStarted = await picker.bind(owner: picker.owner) else { return XCTFail() }
        XCTAssertFalse(api.calls.contains { $0.method == "POST" }); XCTAssertTrue(evidence.unknownIDs.isEmpty)
    }
    func testCloseResumeKeepsUnsettledWriteGateAndDiscardsChildReceipt() async throws {
        let (api, evidence, picker) = try await make(); try await loaded(picker, api)
        XCTAssertTrue(picker.toggle(id: "é", selected: true, owner: picker.owner)); let owner = picker.owner, base = api.calls.count
        let task = Task { await picker.bind(owner: owner) }; try await reached { api.held[base] != nil }
        picker.stop(); picker.resume(); XCTAssertTrue(picker.isSubmitting); XCTAssertFalse(picker.canBind)
        try api.reply(base, summary(version: 3, sources: ["bound", "é"]))
        guard case .discarded = await task.value else { return XCTFail("Old child receipt accepted") }
        XCTAssertFalse(picker.isSubmitting); XCTAssertTrue(picker.selectedIDs.isEmpty)
        XCTAssertEqual(evidence.lastConfirmation?.version, 3); XCTAssertTrue(evidence.unknownIDs.isEmpty)
    }
    func testCancellationAfterDispatchKeepsParentUncertainty() async throws {
        let (api, evidence, picker) = try await make(); try await loaded(picker, api)
        XCTAssertTrue(picker.toggle(id: "é", selected: true, owner: picker.owner)); let base = api.calls.count, owner = picker.owner
        let task = Task { await picker.bind(owner: owner) }; try await reached { api.held[base] != nil }
        task.cancel(); try api.reply(base, summary(version: 3))
        guard case .discarded = await task.value else { return XCTFail() }
        XCTAssertEqual(evidence.unknownIDs, ["9101"]); XCTAssertFalse(picker.canBind); XCTAssertEqual(picker.selectedCount, 1)
    }
    func testReadNotificationDepartureDoesNotDispatch() async throws {
        let (api, _, picker) = try await make(); let count = api.calls.count
        withObservationTracking { _ = picker.catalog.isLoading } onChange: { MainActor.assumeIsolated { picker.stop() } }
        await picker.refreshCatalog()
        XCTAssertEqual(api.calls.count, count); XCTAssertFalse(picker.catalog.isLoading); XCTAssertNil(picker.catalog.value)
    }
    func testInheritedAndLegacyTargetsCannotBind() async throws {
        for legacy in [false, true] {
            let (api, _, picker) = try await make(inherited: !legacy, legacy: legacy); try await loaded(picker, api)
            XCTAssertTrue(picker.toggle(id: "é", selected: true, owner: picker.owner)); XCTAssertFalse(picker.canBind)
            guard case .notStarted = await picker.bind(owner: picker.owner) else { return XCTFail() }
            XCTAssertFalse(api.calls.contains { $0.method == "POST" })
        }
    }
}

extension CapturedTrafficPickerTests {
    func testSelectionNotificationCannotRestoreClosedChoiceOntoAnotherFinding() async throws {
        let (api, evidence, picker) = try await make(); try await loaded(picker, api)
        XCTAssertTrue(picker.toggle(id: "é", selected: true, owner: picker.owner))
        withObservationTracking { _ = picker.selectedIDs } onChange: { MainActor.assumeIsolated { picker.stop() } }
        XCTAssertFalse(picker.toggle(id: "e\u{301}", selected: true, owner: picker.owner))
        XCTAssertTrue(picker.selectedIDs.isEmpty)
        let other = try BackendJSONCoding.decode(FindingRecord.self, from: Data(#"{"id":"9102","finding_id":"9102","task_id":"8102","vulnclass":"CWE-79","severity":"high","status":"pending","summary":"","evidence":"","ts":"raw"}"#.utf8))
        XCTAssertTrue(evidence.select(other)); picker.resume()
        XCTAssertTrue(picker.selectedIDs.isEmpty)
    }
    func testResumeNotificationCannotRecursivelyResume() async throws {
        let (_, _, picker) = try await make(); picker.stop()
        var notifications = 0
        withObservationTracking { _ = picker.owner } onChange: {
            MainActor.assumeIsolated { notifications += 1; if notifications < 4 { picker.resume() } }
        }
        picker.resume(); XCTAssertEqual(notifications, 1); XCTAssertTrue(picker.isCurrent)
    }
    func testStopNotificationCannotReactivatePicker() async throws {
        let (_, _, picker) = try await make()
        var notifications = 0
        withObservationTracking { _ = picker.owner } onChange: {
            MainActor.assumeIsolated { notifications += 1; if notifications < 4 { picker.resume() } }
        }
        picker.stop(); XCTAssertEqual(notifications, 1); XCTAssertFalse(picker.isCurrent)
    }
    func testDepartureRequestedDuringResumeWins() async throws {
        let (_, _, picker) = try await make(); picker.stop()
        withObservationTracking { _ = picker.owner } onChange: { MainActor.assumeIsolated { picker.stop() } }
        picker.resume(); XCTAssertFalse(picker.isCurrent)
    }
}

extension CapturedTrafficPickerTests {
    func testPreviewSelectionPublicationCannotRestoreClosedID() async throws {
        let (api, _, picker) = try await make(); try await loaded(picker, api)
        withObservationTracking { _ = picker.selectedPreviewID } onChange: { MainActor.assumeIsolated { picker.stop() } }
        XCTAssertFalse(picker.selectPreview(id: "é", owner: picker.owner))
        XCTAssertNil(picker.selectedPreviewID); XCTAssertNil(picker.preview.value)
    }
    func testConfirmationCleanupDepartureCannotPublishCurrentChildSuccess() async throws {
        let (api, evidence, picker) = try await make(); try await loaded(picker, api)
        XCTAssertTrue(picker.toggle(id: "é", selected: true, owner: picker.owner)); let base = api.calls.count, owner = picker.owner
        let task = Task { await picker.bind(owner: owner) }; try await reached { api.held[base] != nil }
        // Arm after dispatch, so equal-value preflight notifications cannot choose the test phase.
        withObservationTracking { _ = evidence.lastConfirmation } onChange: {
            MainActor.assumeIsolated {
                withObservationTracking { _ = picker.selectedIDs } onChange: { MainActor.assumeIsolated { picker.stop() } }
            }
        }
        try api.reply(base, summary(version: 3))
        guard case .discarded = await task.value else { return XCTFail("Departure during cleanup accepted old child receipt") }
        XCTAssertEqual(evidence.lastConfirmation?.version, 3); XCTAssertFalse(picker.isCurrent)
    }
}
