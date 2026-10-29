import AppKit
import ArtexCore
import Observation
import SwiftUI
import XCTest
@testable import ArtexMac

@MainActor private final class LinkClock {
    struct Wait { let duration: Duration; let continuation: CheckedContinuation<Void, any Error> }
    var waits: [Wait] = []
    func sleep(_ duration: Duration) async throws { try await withCheckedThrowingContinuation { waits.append(.init(duration: duration, continuation: $0)) } }
    func fireSearch() {
        let selected = waits.filter { $0.duration == .milliseconds(250) }; waits.removeAll { $0.duration == .milliseconds(250) }
        for value in selected { value.continuation.resume() }
    }
    func release() { let old = waits; waits = []; for value in old { value.continuation.resume(throwing: CancellationError()) } }
}
private struct LinkPost: Decodable { struct Ref: Decodable { let trafficId: String }; let trafficRefs: [Ref] }
@MainActor private final class LinkAPI: BackendJSONTransport {
    var paths: [String] = [], methods: [String] = []
    var holdSearch = false, holdWrite = false, failWrite = false
    var searches: [CheckedContinuation<BackendHTTPResponse, any Error>] = []
    var writes: [CheckedContinuation<BackendHTTPResponse, any Error>] = []
    var bound: [String] = []
    var onSend: (@MainActor (String) -> Void)?
    func reply(_ object: Any, status: Int = 200) throws -> BackendHTTPResponse { .init(status: status, body: try JSONSerialization.data(withJSONObject: object)) }
    func row(_ id: String, inherited: Bool = false, legacy: Bool = false) -> [String: Any] {
        var row: [String: Any] = ["id": id, "finding_id": id, "task_id": "11", "name": "\u{FEFF}e\u{301} 中文 한국어", "vulnclass": "CWE-79", "severity": "high", "status": "pending", "summary": "literal summary", "evidence": "raw", "ts": "raw"]
        if inherited { row["inherited"] = true; row["source_task_id"] = "11" }; if legacy { row.removeValue(forKey: "finding_id") }; return row
    }
    func candidates(page: Int64 = 1) throws -> BackendHTTPResponse {
        try reply(["items": page == 1 ? [row("7"), row("8", inherited: true), row("9", legacy: true)] : [row("10")], "page": page, "page_size": 20, "total": 30])
    }
    func summary(owner: String = "7", status: Int = 200) throws -> BackendHTTPResponse {
        let bindings: [[String: Any]] = bound.enumerated().map { index, source in
            let snapshot = "snapshot" + String(index)
            return ["id": String(index + 1), "finding_id": owner, "snapshot_id": snapshot, "role": "supporting", "note": "", "position": index, "created_at": "raw", "snapshot": ["id": snapshot, "source_traffic_id": source, "captured_at": 0, "url": "http://fixture.invalid/", "method": "GET", "content_type": "text/plain", "status": 200, "req_hash": "r", "resp_hash": "s", "req_len": 0, "resp_len": 0]]
        }
        return try reply(["finding_id": owner, "version": bound.isEmpty ? 1 : 2, "report_version": 0, "bindings": bindings], status: status)
    }
    func send(method: String, path: String, body: Data?, bearer: String?) async throws -> BackendHTTPResponse {
        methods.append(method); paths.append(path); onSend?(method)
        if path.hasPrefix("/api/exploration/findings?") {
            if holdSearch { return try await withCheckedThrowingContinuation { searches.append($0) } }
            let page = Int64(URLComponents(string: path)?.queryItems?.first { $0.name == "page" }?.value ?? "1") ?? 1
            return try candidates(page: page)
        }
        if path.hasPrefix("/api/exploration/findings/") {
            let owner = String(path.split(separator: "/")[3])
            if method == "POST" {
                bound = try BackendJSONCoding.decode(LinkPost.self, from: XCTUnwrap(body)).trafficRefs.map(\.trafficId)
                if holdWrite { return try await withCheckedThrowingContinuation { writes.append($0) } }
                return try summary(owner: owner, status: failWrite ? 503 : 200)
            }
            return try summary(owner: owner)
        }
        if path == "/api/traffic/hosts" { return try reply(["hosts": []]) }
        if path == "/api/settings" { return try reply(["traffic_capture": true]) }
        let items = URLComponents(string: path)?.queryItems ?? [], page = Int64(items.first { $0.name == "page" }?.value ?? "0") ?? 0
        return try reply(["enabled": true, "count": 100, "total": 100, "page": page, "size": 50, "exchanges": (page == 0 ? ["é", "e\u{301}"] : ["next"]).map { ["id": $0, "ts": "raw", "host": "fixture", "url": "http://fixture.invalid/", "method": "GET", "content_type": "text/plain", "status": 200, "resp_len": 0] as [String: Any] }])
    }
}
@MainActor final class TrafficLinkingTests: XCTestCase {
    private func assertTrue(_ value: Bool, file: StaticString = #filePath, line: UInt = #line) { XCTAssertTrue(value, file: file, line: line) }
    private func assertFalse(_ value: Bool, file: StaticString = #filePath, line: UInt = #line) { XCTAssertFalse(value, file: file, line: line) }
    private func reached(_ predicate: () -> Bool) async throws {
        for _ in 0..<10000 { if predicate() { return }; await Task.yield() }; XCTFail("Missing handoff"); throw CancellationError()
    }
    private func fixture() async throws -> (TrafficScreenModel, LinkAPI, LinkClock, UUID) {
        let api = LinkAPI(), clock = LinkClock()
        let model = TrafficScreenModel(store: TrafficStore(service: .init(client: api)), findings: FindingService(client: api), binding: FindingTrafficService(client: api), sleep: clock.sleep)
        let lease = try XCTUnwrap(model.begin()); try await reached { !model.store.isRefreshing && model.store.catalog.value != nil }
        XCTAssertTrue(model.toggleFlow("é", selected: true, lease: lease, owner: model.store.owner))
        XCTAssertTrue(model.toggleFlow("e\u{301}", selected: true, lease: lease, owner: model.store.owner))
        return (model, api, clock, lease)
    }
    private func open(_ model: TrafficScreenModel, _ clock: LinkClock, _ lease: UUID) async throws -> TrafficLinkWorkspace {
        XCTAssertTrue(model.openLink(lease: lease, owner: model.store.owner, revision: model.store.flowRevision))
        let workspace = try XCTUnwrap(model.linkWorkspace)
        try await reached { clock.waits.contains { $0.duration == .milliseconds(250) } }; clock.fireSearch()
        try await reached { workspace.candidates != nil && !workspace.isLoading }
        return workspace
    }
    private func choose(_ workspace: TrafficLinkWorkspace) async throws {
        let target = try XCTUnwrap(workspace.candidates?.items.first)
        assertTrue(await workspace.choose(target.identity, ticket: workspace.searchTicket))
        XCTAssertTrue(workspace.canSubmit)
    }
    func testCandidateServicePreservesTrimmedSearchAndReadOnlyRows() async throws {
        let api = LinkAPI(), service = FindingService(client: api)
        let page = try await service.bindingCandidates(search: " \u{FEFF}e\u{301}+中文 한국어 ", page: 1)
        XCTAssertEqual(page.items.count, 3); XCTAssertTrue(page.items[0].canMutate); XCTAssertFalse(page.items[1].canMutate); XCTAssertFalse(page.items[2].canMutate)
        let query = try XCTUnwrap(URLComponents(string: XCTUnwrap(api.paths.last))?.queryItems)
        XCTAssertEqual(query.first { $0.name == "limit" }?.value, "20")
        XCTAssertEqual(Data(try XCTUnwrap(query.first { $0.name == "q" }?.value).utf8), Data("e\u{301}+中文 한국어".utf8))
    }
    func testCrossPageLiteralSelectionBindsAndClearsOnlyCurrentScope() async throws {
        let (model, api, clock, lease) = try await fixture(); defer { model.reset(); clock.release() }
        XCTAssertTrue(model.page(1, lease: lease, owner: model.store.owner)); try await reached { !model.store.isRefreshing && !model.store.catalog.isStale }
        XCTAssertTrue(model.toggleFlow("next", selected: true, lease: lease, owner: model.store.owner))
        let workspace = try await open(model, clock, lease); try await choose(workspace)
        assertTrue(await workspace.submit(id: workspace.binding.requestID, owner: workspace.binding.owner))
        XCTAssertEqual(api.bound.map { Data($0.utf8) }, ["é", "e\u{301}", "next"].map { Data($0.utf8) })
        XCTAssertTrue(model.store.selectedFlowIDs.isEmpty); XCTAssertNil(model.linkWorkspace); XCTAssertEqual(model.linkedCount, 3)
    }
    func testReadonlyTargetsAndOldSearchTicketCannotSelect() async throws {
        let (model, api, clock, lease) = try await fixture(); defer { model.reset(); clock.release() }
        let workspace = try await open(model, clock, lease), ticket = workspace.searchTicket
        let rows = try XCTUnwrap(workspace.candidates).items
        assertFalse(await workspace.choose(rows[1].identity, ticket: ticket)); assertFalse(await workspace.choose(rows[2].identity, ticket: ticket))
        XCTAssertTrue(workspace.edit("new query")); assertFalse(await workspace.choose(rows[0].identity, ticket: ticket))
        XCTAssertTrue(api.methods.allSatisfy { $0 == "GET" }); XCTAssertNil(workspace.selectedTarget)
    }
    func testSelectionPersistsAcrossSearchPagesAndLatestRawQueryWins() async throws {
        let (model, api, clock, lease) = try await fixture(); defer { model.reset(); clock.release() }
        let workspace = try await open(model, clock, lease); try await choose(workspace)
        XCTAssertTrue(workspace.edit("first")); try await reached { clock.waits.contains { $0.duration == .milliseconds(250) } }
        XCTAssertTrue(workspace.edit(" \u{FEFF}e\u{301}+中文 ")); try await reached { clock.waits.filter { $0.duration == .milliseconds(250) }.count == 2 }; clock.fireSearch()
        try await reached { !workspace.isLoading && workspace.pageIsCurrent }
        XCTAssertEqual(workspace.selectedTarget?.findingId, "7"); XCTAssertTrue(workspace.canSubmit)
        XCTAssertFalse(api.paths.contains { $0.contains("q=first") })
        XCTAssertTrue(workspace.page(1, ticket: workspace.searchTicket)); try await reached { clock.waits.contains { $0.duration == .milliseconds(250) } }; clock.fireSearch()
        try await reached { !workspace.isLoading && workspace.pageIsCurrent }
        XCTAssertEqual(workspace.pageNumber, 2); XCTAssertEqual(workspace.selectedTarget?.findingId, "7"); XCTAssertTrue(workspace.canSubmit)
    }
    func testLinkModalBlocksDeletionAndOldFlowSetters() async throws {
        let (model, _, clock, lease) = try await fixture(); defer { model.reset(); clock.release() }
        let owner = model.store.owner, revision = model.store.flowRevision
        let toggle = TrafficBindings.flow(model, id: "é", lease: lease, owner: owner)
        let workspace = try await open(model, clock, lease)
        toggle.wrappedValue = false; XCTAssertEqual(model.store.flowRevision, revision)
        XCTAssertFalse(model.prepareDeletion(.purgeAll, lease: lease, owner: owner))
        XCTAssertTrue(model.closeLink(id: workspace.id, lease: lease)); XCTAssertEqual(model.store.selectedFlowIDs.count, 2)
        XCTAssertFalse(model.clearFlows(lease: lease, owner: owner, revision: UUID()))
    }
    func testChangedSelectionAfterDispatchIsPreserved() async throws {
        let (model, api, clock, lease) = try await fixture(); defer { model.reset(); clock.release() }
        let workspace = try await open(model, clock, lease); try await choose(workspace)
        api.holdWrite = true
        let job = Task { await workspace.submit(id: workspace.binding.requestID, owner: workspace.binding.owner) }
        try await reached { api.writes.count == 1 }
        XCTAssertTrue(model.store.toggleFlow(id: "é", selected: false, owner: model.store.owner))
        api.writes.removeFirst().resume(returning: try api.summary())
        assertFalse(await job.value); XCTAssertEqual(model.store.selectedFlowIDs.map { Data($0.utf8) }, [Data("e\u{301}".utf8)])
        XCTAssertNil(model.linkWorkspace); XCTAssertTrue(model.linkSelectionPreserved)
    }
    func testResetDuringSubmittingPublicationRevokesPostAndScrubs() async throws {
        let (model, api, clock, lease) = try await fixture(); defer { model.reset(); clock.release() }
        let workspace = try await open(model, clock, lease); try await choose(workspace)
        withObservationTracking { _ = workspace.isSubmitting } onChange: { MainActor.assumeIsolated { model.reset() } }
        assertFalse(await workspace.submit(id: workspace.binding.requestID, owner: workspace.binding.owner))
        XCTAssertFalse(api.methods.contains("POST")); XCTAssertNil(model.linkWorkspace); XCTAssertTrue(workspace.sourceIDs.isEmpty); XCTAssertNil(workspace.selectedTarget)
    }
    func testParentScopeLossDuringCoreBusyPublicationPreventsDispatch() async throws {
        let (model, api, clock, lease) = try await fixture(); defer { model.reset(); clock.release() }
        let workspace = try await open(model, clock, lease); try await choose(workspace)
        withObservationTracking { _ = workspace.binding.isMutating } onChange: {
            MainActor.assumeIsolated { _ = model.store.clearFlowSelection(owner: model.store.owner) }
        }
        assertFalse(await workspace.submit(id: workspace.binding.requestID, owner: workspace.binding.owner))
        XCTAssertFalse(api.methods.contains("POST")); XCTAssertFalse(workspace.binding.hasUnknownOutcome)
    }
    func testUnknownSurvivesCloseBlocksDeletionAndExplicitRecoveryDoesNotPost() async throws {
        let (model, api, clock, lease) = try await fixture(); defer { model.reset(); clock.release() }
        let workspace = try await open(model, clock, lease); try await choose(workspace); api.failWrite = true
        assertFalse(await workspace.submit(id: workspace.binding.requestID, owner: workspace.binding.owner))
        XCTAssertTrue(model.linkHasUnknown); XCTAssertTrue(model.closeLink(id: workspace.id, lease: lease))
        XCTAssertFalse(model.prepareDeletion(.purgeAll, lease: lease, owner: model.store.owner))
        XCTAssertFalse(model.openLink(lease: lease, owner: model.store.owner, revision: model.store.flowRevision))
        XCTAssertTrue(model.openLinkRecovery(lease: lease)); let recovery = try XCTUnwrap(model.linkWorkspace)
        await recovery.recover(owner: recovery.binding.owner)
        XCTAssertTrue(recovery.binding.canAcknowledgeUnknown); XCTAssertTrue(model.linkHasUnknown)
        XCTAssertTrue(recovery.acknowledge(owner: recovery.binding.owner, revision: recovery.binding.unknownRevision))
        XCTAssertNil(model.linkWorkspace); XCTAssertFalse(model.linkHasUnknown); XCTAssertEqual(model.store.selectedFlowIDs.count, 2)
        XCTAssertEqual(api.methods.filter { $0 == "POST" }.count, 1)
    }
    func testHeldWriteResetKeepsSharedGateAndDiscardsLateReceipt() async throws {
        let (model, api, clock, lease) = try await fixture(); defer { model.reset(); clock.release() }
        let workspace = try await open(model, clock, lease); try await choose(workspace); api.holdWrite = true
        let job = Task { await workspace.submit(id: workspace.binding.requestID, owner: workspace.binding.owner) }; try await reached { api.writes.count == 1 }
        model.reset(); let next = try XCTUnwrap(model.begin())
        XCTAssertFalse(model.controlsAvailable); XCTAssertTrue(model.linkHasUnknown)
        XCTAssertFalse(model.prepareDeletion(.purgeAll, lease: next, owner: model.store.owner))
        api.writes.removeFirst().resume(returning: try api.summary()); assertFalse(await job.value)
        XCTAssertNil(model.linkWorkspace); XCTAssertNil(workspace.selectedTarget); XCTAssertTrue(workspace.sourceIDs.isEmpty); XCTAssertTrue(model.linkHasUnknown)
    }
    func testLateCandidateReadAndStaleDismissCannotAffectReplacement() async throws {
        let (model, api, clock, lease) = try await fixture(); defer { model.reset(); clock.release() }
        let workspace = try await open(model, clock, lease), old = workspace.id
        api.holdSearch = true; XCTAssertTrue(workspace.edit("held")); try await reached { clock.waits.contains { $0.duration == .milliseconds(250) } }; clock.fireSearch()
        try await reached { api.searches.count == 1 }; XCTAssertTrue(model.closeLink(id: old, lease: lease))
        api.holdSearch = false; let next = try await open(model, clock, lease)
        XCTAssertFalse(model.closeLink(id: old, lease: lease))
        api.searches.removeFirst().resume(returning: try api.candidates(page: 2))
        for _ in 0..<20 { await Task.yield() }
        XCTAssertNil(workspace.candidates); XCTAssertEqual(workspace.searchDraft, ""); XCTAssertEqual(model.linkWorkspace?.id, next.id)
    }
    func testEncodedCandidatePathLimitRejectsBeforeTransport() async throws {
        let api = LinkAPI(), service = FindingService(client: api)
        do { _ = try await service.bindingCandidates(search: String(repeating: "中", count: 1000), page: 1); XCTFail("Encoded query exceeds the boundary") }
        catch { XCTAssertTrue(error is FindingInputError) }
        XCTAssertTrue(api.paths.isEmpty)
    }
    func testCandidateFailureKeepsStaleRowsAndExplicitRetry() async throws {
        let (model, api, clock, lease) = try await fixture(); defer { model.reset(); clock.release() }
        let workspace = try await open(model, clock, lease)
        api.holdSearch = true; XCTAssertTrue(workspace.edit("error"))
        try await reached { clock.waits.contains { $0.duration == .milliseconds(250) } }; clock.fireSearch()
        try await reached { api.searches.count == 1 }
        api.searches.removeFirst().resume(returning: try api.reply(["error": "secret raw server error"], status: 503))
        try await reached { !workspace.isLoading }
        XCTAssertNotNil(workspace.failure); XCTAssertNotNil(workspace.candidates); XCTAssertFalse(workspace.pageIsCurrent)
        let row = try XCTUnwrap(workspace.candidates?.items.first)
        assertFalse(await workspace.choose(row.identity, ticket: workspace.searchTicket))
        api.holdSearch = false; workspace.reloadCandidates(ticket: workspace.searchTicket)
        try await reached { clock.waits.contains { $0.duration == .milliseconds(250) } }; clock.fireSearch()
        try await reached { workspace.pageIsCurrent && !workspace.isLoading }
        XCTAssertNil(workspace.failure)
    }
    func testCandidatePublicationDepartureScrubsAfterUpdate() async throws {
        let (model, api, clock, lease) = try await fixture(); defer { model.reset(); clock.release() }
        let workspace = try await open(model, clock, lease)
        api.holdSearch = true; XCTAssertTrue(workspace.edit("sensitive"))
        try await reached { clock.waits.contains { $0.duration == .milliseconds(250) } }; clock.fireSearch()
        try await reached { api.searches.count == 1 }
        withObservationTracking { _ = workspace.candidates } onChange: { MainActor.assumeIsolated { _ = model.closeLink(id: workspace.id, lease: lease) } }
        api.searches.removeFirst().resume(returning: try api.candidates())
        try await reached { model.linkWorkspace == nil }
        XCTAssertNil(workspace.candidates); XCTAssertNil(workspace.selectedTarget); XCTAssertTrue(workspace.sourceIDs.isEmpty); XCTAssertEqual(workspace.searchDraft, "")
    }
    func testWrongCandidatePageCannotReplaceFreshGeneration() async throws {
        let (model, api, clock, lease) = try await fixture(); defer { model.reset(); clock.release() }
        let workspace = try await open(model, clock, lease)
        api.holdSearch = true; XCTAssertTrue(workspace.page(1, ticket: workspace.searchTicket))
        try await reached { clock.waits.contains { $0.duration == .milliseconds(250) } }; clock.fireSearch()
        try await reached { api.searches.count == 1 }; api.searches.removeFirst().resume(returning: try api.candidates(page: 1))
        try await reached { !workspace.isLoading }
        XCTAssertNotNil(workspace.failure); XCTAssertFalse(workspace.pageIsCurrent); XCTAssertEqual(workspace.candidates?.page, 1)
    }
    func testStaleSubmitAndAcknowledgmentNeverDispatch() async throws {
        let (model, api, clock, lease) = try await fixture(); defer { model.reset(); clock.release() }
        let workspace = try await open(model, clock, lease); try await choose(workspace)
        assertFalse(await workspace.submit(id: UUID(), owner: workspace.binding.owner))
        assertFalse(await workspace.submit(id: workspace.binding.requestID, owner: UUID()))
        XCTAssertFalse(workspace.acknowledge(owner: workspace.binding.owner, revision: UUID()))
        XCTAssertFalse(api.methods.contains("POST"))
    }
    func testCandidateSeverityLabelsFollowLocaleAndPreserveCustomData() {
        for language in AppLanguage.allCases {
            for raw in ["critical", "high", "medium", "low", "info"] {
                XCTAssertEqual(TrafficLinkDialog.severityLabel(raw, language: language), DashboardLabels.text(raw, domain: .severity, language: language))
            }
            let literal = "\u{FEFF}e\u{301} 中文 한국어"
            XCTAssertEqual(Data(TrafficLinkDialog.severityLabel(literal, language: language).utf8), Data(literal.utf8))
        }
        XCTAssertNotEqual(TrafficLinkDialog.severityLabel("high", language: .japanese), "high")
    }
    func testOffscreenLinkDialogBothLanguagesHasNoIOOrMutation() async throws {
        let (model, api, clock, lease) = try await fixture(); defer { model.reset(); clock.release() }
        let workspace = try await open(model, clock, lease); try await choose(workspace)
        let count = api.paths.count
        for language in AppLanguage.allCases { for scheme in [ColorScheme.light, .dark] {
            let host = NSHostingView(rootView: TrafficLinkDialog(model: model, lease: lease, id: workspace.id).environment(\.locale, language.locale).environment(\.colorScheme, scheme))
            for width in [620.0, 900.0] { host.frame = NSRect(x: 0, y: 0, width: width, height: 700); host.layoutSubtreeIfNeeded(); XCTAssertNil(host.window) }
        } }
        XCTAssertEqual(api.paths.count, count); XCTAssertFalse(api.methods.contains("POST"))
    }
}
