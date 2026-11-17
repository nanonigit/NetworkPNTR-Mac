import AppKit
import NetworkPNTRCore
import SwiftUI
import XCTest
@testable import NetworkPNTRMac

@MainActor private final class TrafficUIAPI: BackendJSONTransport {
    var methods: [String] = [], paths: [String] = []
    var failWrite = false, holdWrite = false
    var heldWrites: [CheckedContinuation<BackendHTTPResponse, any Error>] = []
    let raw = "\u{FEFF}GET /e\u{301} HTTP/1.1\r\nX-Literal: 中文 한국어\r\n\r\n@blob sha256:literal"
    func send(method: String, path: String, body: Data?, bearer: String?) async throws -> BackendHTTPResponse {
        methods.append(method); paths.append(path)
        let object: Any
        if method != "GET" {
            if holdWrite { return try await withCheckedThrowingContinuation { heldWrites.append($0) } }
            object = ["deleted": 2, "reclaimed": 4096]
        }
        else if path == "/api/traffic/hosts" { object = ["hosts": [["host": "é", "count": 1], ["host": "e\u{301}", "count": 2]]] }
        else if path == "/api/settings" { object = ["traffic_capture": true] }
        else if path.hasPrefix("/api/traffic/exchange?") { object = ["req": raw, "resp": "HTTP/1.1 200 OK\n\n中文 한국어 e\u{301}"] }
        else {
            let items = URLComponents(string: path)?.queryItems ?? []
            let page = Int64(items.first { $0.name == "page" }?.value ?? "0") ?? 0
            let size = Int(items.first { $0.name == "size" }?.value ?? "50") ?? 50
            object = ["enabled": true, "proxy": "127.0.0.1:8788", "count": 100, "total": 100, "page": page, "size": size,
                      "exchanges": ["é", "e\u{301}"].map { ["id": $0, "ts": "literal time", "host": $0, "method": "GET", "url": "https://example.invalid/path", "content_type": "text/plain", "status": 200, "resp_len": 1] as [String: Any] }]
        }
        return .init(status: method != "GET" && failWrite ? 503 : 200, body: try JSONSerialization.data(withJSONObject: object))
    }
}

@MainActor final class TrafficUITests: XCTestCase {
    private func reached(_ predicate: () -> Bool) async throws {
        for _ in 0..<10000 { if predicate() { return }; await Task.yield() }
        XCTFail("Missing controlled handoff"); throw CancellationError()
    }
    private func fixture() async throws -> (TrafficScreenModel, TrafficUIAPI, UUID) {
        let api = TrafficUIAPI()
        let screen = TrafficScreenModel(store: TrafficStore(service: .init(client: api)))
        let lease = try XCTUnwrap(screen.begin())
        try await reached { !screen.store.isRefreshing && screen.store.catalog.value != nil && screen.store.hosts.value != nil }
        return (screen, api, lease)
    }
    func testRequestHostCompletionPreservesOriginalAndExistingHeaders() {
        let raw = "GET / HTTP/1.1\r\nX-Raw: \u{FEFF}e\u{301} 中文 한국어\r\n\r\n"
        let expected = "GET / HTTP/1.1\r\nHost: example.invalid\r\nX-Raw: \u{FEFF}e\u{301} 中文 한국어\r\n\r\n"
        XCTAssertEqual(Data(TrafficPresentation.request(raw, url: "https://example.invalid/path", host: "fallback").utf8), Data(expected.utf8))
        XCTAssertEqual(Data(raw.utf8), Data("GET / HTTP/1.1\r\nX-Raw: \u{FEFF}e\u{301} 中文 한국어\r\n\r\n".utf8))
        for value in ["", " \u{FEFF} ", "GET /\nHOST\u{FEFF}: literal\n", "GET /\u{2028}Host: literal\n", "GET /\nHost\n:\n"] {
            XCTAssertEqual(Data(TrafficPresentation.request(value, url: "https://other.invalid", host: "fallback").utf8), Data(value.utf8))
        }
        XCTAssertEqual(TrafficPresentation.request("GET /", url: "/relative", host: "fallback"), "GET /\nHost: fallback")
        XCTAssertEqual(TrafficPresentation.request("GET /\n\n", url: "https://example.invalid:8443/", host: "fallback"), "GET /\nHost: example.invalid:8443\n\n")
        XCTAssertEqual(TrafficPresentation.request("GET /", url: "http://example.invalid:80/", host: "fallback"), "GET /\nHost: example.invalid")
        XCTAssertEqual(TrafficPresentation.request("GET /", url: "https://[::1]:8443/", host: "fallback"), "GET /\nHost: [::1]:8443")
        XCTAssertEqual(TrafficPresentation.request("GET /", url: "https://example.invalid:999999/", host: "fallback"), "GET /\nHost: fallback")
    }
    func testTextControlsHostIdentityAndPreviewDismissRejectRetiredScopes() async throws {
        let (model, _, lease) = try await fixture(); defer { model.reset() }
        let owner = model.store.owner
        let first = TrafficBindings.host(model, host: "é", lease: lease, owner: owner)
        let second = TrafficBindings.host(model, host: "e\u{301}", lease: lease, owner: owner)
        first.wrappedValue = true; second.wrappedValue = true
        XCTAssertEqual(model.store.selectedHosts.map { Data($0.utf8) }, [Data("é".utf8), Data("e\u{301}".utf8)])
        await model.selectDetail("é", lease: lease, owner: owner)
        let revision = model.previewRevision
        let dismiss = TrafficBindings.preview(model, lease: lease, owner: owner, revision: revision, id: "é")
        XCTAssertTrue(dismiss.wrappedValue); dismiss.wrappedValue = false
        await model.selectDetail("é", lease: lease, owner: owner)
        dismiss.wrappedValue = false
        XCTAssertNotNil(model.store.selectedExchange); XCTAssertNotEqual(model.previewRevision, revision)
        let text = TrafficBindings.text(model, field: .host, lease: lease)
        let method = TrafficBindings.method(model, lease: lease, owner: owner)
        let next = try XCTUnwrap(model.begin())
        text.wrappedValue = "retired"; method.wrappedValue = "POST"; first.wrappedValue = true
        XCTAssertEqual(model.text(.host, lease: next), ""); XCTAssertNil(model.store.query.method); XCTAssertTrue(model.store.selectedHosts.isEmpty)
    }
    func testDeletionBindingsFreezeDialogAndCannotReplayOrDismissReplacement() async throws {
        let (model, api, lease) = try await fixture(); defer { model.reset() }
        let owner = model.store.owner
        XCTAssertFalse(model.prepareDeletion(.capture(false), lease: lease, owner: owner))
        XCTAssertTrue(model.prepareDeletion(.purgeAll, lease: lease, owner: owner))
        let old = try XCTUnwrap(model.store.confirmation)
        let dismiss = TrafficBindings.confirmation(model, lease: lease, id: old.id, owner: owner)
        XCTAssertTrue(model.cancelDeletion(id: old.id, lease: lease, owner: owner))
        XCTAssertTrue(model.prepareDeletion(.purgeAll, lease: lease, owner: owner))
        let current = try XCTUnwrap(model.store.confirmation)
        dismiss.wrappedValue = nil; XCTAssertEqual(model.store.confirmation?.id, current.id)
        guard case .notStarted = await model.confirmDeletion(id: old.id, lease: lease, owner: owner) else { return XCTFail("Retired confirmation") }
        guard case .confirmed = await model.confirmDeletion(id: current.id, lease: lease, owner: owner) else { return XCTFail("Expected receipt") }
        guard case .notStarted = await model.confirmDeletion(id: current.id, lease: lease, owner: owner) else { return XCTFail("Replay") }
        XCTAssertEqual(api.methods.filter { $0 == "DELETE" }.count, 1)
    }
    func testUnknownRequiresExplicitCurrentReadbackAcknowledgment() async throws {
        let (model, api, lease) = try await fixture(); defer { model.reset() }
        api.failWrite = true; let owner = model.store.owner
        XCTAssertTrue(model.prepareDeletion(.purgeAll, lease: lease, owner: owner))
        let dialog = try XCTUnwrap(model.store.confirmation)
        guard case .unconfirmed = await model.confirmDeletion(id: dialog.id, lease: lease, owner: owner) else { return XCTFail("Expected unknown") }
        let revision = model.store.unknownRevision
        XCTAssertFalse(model.acknowledge(lease: lease, owner: owner, revision: revision))
        XCTAssertTrue(model.refresh(lease: lease)); try await reached { model.store.canAcknowledgeUnknown }
        XCTAssertTrue(model.store.hasUnknownOutcome)
        XCTAssertFalse(model.acknowledge(lease: UUID(), owner: owner, revision: revision))
        XCTAssertFalse(model.acknowledge(lease: lease, owner: owner, revision: UUID()))
        XCTAssertTrue(model.edit(.host, text: "pending", lease: lease))
        XCTAssertFalse(model.acknowledge(lease: lease, owner: owner, revision: revision))
        XCTAssertTrue(model.store.hasUnknownOutcome)
        XCTAssertTrue(model.edit(.host, text: "", lease: lease))
        XCTAssertTrue(model.acknowledge(lease: lease, owner: owner, revision: revision)); XCTAssertFalse(model.store.hasUnknownOutcome)
    }
    func testPendingDraftAndStaleOwnerCannotPrepareOrSelect() async throws {
        let (model, _, lease) = try await fixture(); defer { model.reset() }
        let owner = model.store.owner
        XCTAssertTrue(model.edit(.host, text: "pending", lease: lease))
        XCTAssertFalse(model.prepareDeletion(.purgeAll, lease: lease, owner: owner))
        await model.selectDetail("é", lease: lease, owner: owner); XCTAssertNil(model.store.selectedExchange)
        XCTAssertFalse(model.prepareDeletion(.purgeAll, lease: lease, owner: UUID()))
    }
    func testBodySaveControlRequiresExactCurrentSupportedPreviewWithoutDispatch() async throws {
        let api = TrafficUIAPI()
        var supported = true
        let model = TrafficScreenModel(store: TrafficStore(service: .init(client: api)), bodyMetadata: { id, side in
            try TrafficBlobDownload(trafficID: id, side: side, expectedSize: 0, expectedSHA256: ArtifactIntegrity.sha256(Data()))
        }, bodyExporter: { _,_ in throw CancellationError() }, bodyAvailable: { supported })
        let lease = try XCTUnwrap(model.begin()); defer { model.reset() }
        try await reached { !model.store.isRefreshing && api.paths.count == 3 }
        await model.selectDetail("é", lease: lease, owner: model.store.owner)
        let owner = model.store.owner, revision = model.previewRevision, count = api.paths.count
        let current = TrafficRawPreview(model: model, lease: lease, owner: owner, revision: revision, id: "é")
        XCTAssertNotNil(current.ownedExport)
        supported = false; XCTAssertNil(current.ownedExport)
        supported = true
        XCTAssertNil(TrafficRawPreview(model: model, lease: UUID(), owner: owner, revision: revision, id: "é").ownedExport)
        XCTAssertNil(TrafficRawPreview(model: model, lease: lease, owner: UUID(), revision: revision, id: "é").ownedExport)
        XCTAssertNil(TrafficRawPreview(model: model, lease: lease, owner: owner, revision: UUID(), id: "é").ownedExport)
        XCTAssertNil(TrafficRawPreview(model: model, lease: lease, owner: owner, revision: revision, id: "e\u{301}").ownedExport)
        XCTAssertEqual(api.paths.count, count)
    }
    func testOwnedTrafficLabelsHaveEnglishJapaneseTranslations() {
        let keys = AppStringKey.allCases.filter { $0.rawValue.hasPrefix("traffic.ui.") }
        XCTAssertGreaterThan(keys.count, 35)
        for key in keys { for language in AppLanguage.allCases {
            let text = AppStrings.text(key, language: language)
            XCTAssertNotEqual(text, key.rawValue); XCTAssertFalse(text.isEmpty)
            XCTAssertFalse(text.unicodeScalars.contains { (0xAC00...0xD7AF).contains($0.value) })
        } }
    }
    func testOffscreenReadPreviewAndConfirmationLayoutsHaveNoTransportSideEffects() async throws {
        let (model, api, lease) = try await fixture(); defer { model.reset() }
        await model.selectDetail("é", lease: lease, owner: model.store.owner)
        let raw = try XCTUnwrap(model.store.detail.value).request
        let before = api.paths.count
        for language in AppLanguage.allCases { for scheme in [ColorScheme.light, .dark] {
            let host = NSHostingView(rootView: TrafficContent(model: model, lease: lease).environment(\.locale, language.locale).environment(\.colorScheme, scheme))
            for width in [900.0, 1440.0] { host.frame = NSRect(x: 0, y: 0, width: width, height: 800); host.layoutSubtreeIfNeeded(); XCTAssertNil(host.window) }
            let preview = NSHostingView(rootView: TrafficRawPreview(model: model, lease: lease, owner: model.store.owner, revision: model.previewRevision, id: "é").environment(\.locale, language.locale))
            preview.frame = NSRect(x: 0, y: 0, width: 850, height: 650); preview.layoutSubtreeIfNeeded()
        } }
        XCTAssertEqual(api.paths.count, before); XCTAssertEqual(Data(model.store.detail.value!.request.utf8), Data(raw.utf8))
        model.closeDetail("é", lease: lease, owner: model.store.owner, revision: model.previewRevision)
        XCTAssertTrue(model.prepareDeletion(.purgeAll, lease: lease, owner: model.store.owner))
        let context = try XCTUnwrap(model.store.confirmation), count = api.paths.count
        for language in AppLanguage.allCases {
            let host = NSHostingView(rootView: TrafficDeleteDialog(model: model, lease: lease, contextID: context.id).environment(\.locale, language.locale))
            host.frame = NSRect(x: 0, y: 0, width: 600, height: 400); host.layoutSubtreeIfNeeded()
        }
        XCTAssertEqual(api.paths.count, count); XCTAssertTrue(api.methods.allSatisfy { $0 == "GET" })
    }
    func testQueuedPagerAndResetRejectChangedQueryOwner() async throws {
        let (model, _, lease) = try await fixture(); defer { model.reset() }
        let old = model.store.owner
        XCTAssertTrue(model.control(.method(.post), lease: lease))
        try await reached { !model.store.isRefreshing && !model.store.catalog.isStale }
        XCTAssertFalse(model.page(1, lease: lease, owner: old)); XCTAssertEqual(model.store.query.page, 0)
        XCTAssertTrue(model.page(1, lease: lease, owner: model.store.owner))
        try await reached { !model.store.isRefreshing && !model.store.catalog.isStale }
        XCTAssertEqual(model.store.query.page, 1)
        let retired = model.store.owner
        XCTAssertTrue(model.control(.status(.clientError), lease: lease))
        XCTAssertFalse(model.resetAdvanced(lease: lease, owner: retired))
        XCTAssertEqual(TrafficPresentation.status(model.store.query.status), "4xx")
        XCTAssertTrue(model.resetAdvanced(lease: lease, owner: model.store.owner))
    }

    func testNativeRequestDisplayMatches22PinnedBrowserFunctionCases() throws {
        struct Oracle: Decodable { let baseline: String; let cases: [Case] }
        struct Case: Decodable { let raw: String; let url: String; let host: String; let expected: String }
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let oracle = try JSONDecoder().decode(Oracle.self, from: Data(contentsOf: root.appendingPathComponent("evidence/traffic/request-host-oracle.json")))
        XCTAssertEqual(oracle.baseline, "e75ae371ad777ffd1eecdd28d2781a6519b05591"); XCTAssertEqual(oracle.cases.count, 22)
        for item in oracle.cases {
            XCTAssertEqual(Data(TrafficPresentation.request(item.raw, url: item.url, host: item.host).utf8), Data(item.expected.utf8), "URL: \(item.url)")
        }
    }

    func testHeldDeletionRetainsProgressContextThenResetScrubsRetainedDialog() async throws {
        let (model, api, lease) = try await fixture(); defer { model.reset() }
        let owner = model.store.owner
        XCTAssertTrue(model.toggleHost("e\u{301}", selected: true, lease: lease, owner: owner))
        XCTAssertTrue(model.prepareDeletion(.selectedHosts, lease: lease, owner: owner))
        let context = try XCTUnwrap(model.deletionDialog)
        let retained = TrafficDeleteDialog(model: model, lease: lease, contextID: context.id)
        api.holdWrite = true
        let write = Task { await model.confirmDeletion(id: context.id, lease: lease, owner: owner) }
        try await reached { api.heldWrites.count == 1 }
        XCTAssertNotNil(retained.context); XCTAssertEqual(model.deletionDialog?.id, context.id)
        XCTAssertNil(model.store.confirmation); XCTAssertTrue(model.store.isMutating)
        XCTAssertFalse(model.cancelDeletion(id: context.id, lease: lease, owner: owner))
        XCTAssertFalse(model.control(.size(25), lease: lease))
        model.reset()
        XCTAssertNil(model.deletionDialog); XCTAssertNil(retained.context)
        XCTAssertTrue(model.store.hasUnknownOutcome); XCTAssertNil(model.store.unknownChange)
        api.heldWrites.removeFirst().resume(returning: .init(status: 503, body: Data()))
        guard case .discarded = await write.value else { return XCTFail("Retired writer") }
        XCTAssertNil(model.deletionDialog); XCTAssertTrue(model.store.hasUnknownOutcome)
        XCTAssertEqual(api.methods.filter { $0 == "DELETE" }.count, 1)
    }

    func testPreviewBlocksQueuedDeletionAndControlsUntilDismissed() async throws {
        let (model, _, lease) = try await fixture(); defer { model.reset() }
        let owner = model.store.owner
        await model.selectDetail("é", lease: lease, owner: owner)
        XCTAssertNotNil(model.store.selectedExchange)
        XCTAssertFalse(model.prepareDeletion(.purgeAll, lease: lease, owner: owner))
        XCTAssertFalse(model.control(.method(.post), lease: lease))
        XCTAssertNil(model.deletionDialog)
        model.closeDetail("é", lease: lease, owner: owner, revision: model.previewRevision)
        XCTAssertNil(model.store.selectedExchange)
        XCTAssertTrue(model.prepareDeletion(.purgeAll, lease: lease, owner: owner))
    }

    func testPickerBindingsValidateTagsAndFreezeQueryOwner() async throws {
        let (model, api, lease) = try await fixture(); defer { model.reset() }
        let owner = model.store.owner
        let method = TrafficBindings.method(model, lease: lease, owner: owner)
        let staleStatus = TrafficBindings.status(model, lease: lease, owner: owner)
        let staleSize = TrafficBindings.size(model, lease: lease, owner: owner)
        method.wrappedValue = "invalid"; staleStatus.wrappedValue = "1xx"; staleSize.wrappedValue = 500
        XCTAssertNil(model.store.query.method); XCTAssertNil(model.store.query.status); XCTAssertEqual(model.store.query.size, 50)
        XCTAssertEqual(model.store.owner, owner)
        method.wrappedValue = "POST"
        try await reached { !model.store.isRefreshing && !model.store.catalog.isStale }
        XCTAssertEqual(model.store.query.method, .post)
        method.wrappedValue = "GET"; staleStatus.wrappedValue = "4xx"; staleSize.wrappedValue = 25
        XCTAssertEqual(model.store.query.method, .post); XCTAssertNil(model.store.query.status); XCTAssertEqual(model.store.query.size, 50)
        for tag in ["2xx", "3xx", "4xx", "5xx", "all"] {
            let binding = TrafficBindings.status(model, lease: lease, owner: model.store.owner)
            binding.wrappedValue = tag
            try await reached { !model.store.isRefreshing && !model.store.catalog.isStale }
            XCTAssertEqual(binding.wrappedValue, tag)
        }
        for size in [25, 50, 100, 200] {
            let binding = TrafficBindings.size(model, lease: lease, owner: model.store.owner)
            binding.wrappedValue = size
            try await reached { !model.store.isRefreshing && !model.store.catalog.isStale }
            XCTAssertEqual(binding.wrappedValue, size)
        }
        let any = TrafficBindings.method(model, lease: lease, owner: model.store.owner)
        any.wrappedValue = "all"
        try await reached { !model.store.isRefreshing && !model.store.catalog.isStale }
        XCTAssertEqual(any.wrappedValue, "all"); XCTAssertNil(model.store.query.method)
        XCTAssertTrue(api.paths.contains { $0.contains("status=5xx") })
        XCTAssertTrue(api.paths.contains { $0.contains("size=200") })
        XCTAssertTrue(api.methods.allSatisfy { $0 == "GET" })
    }

}
