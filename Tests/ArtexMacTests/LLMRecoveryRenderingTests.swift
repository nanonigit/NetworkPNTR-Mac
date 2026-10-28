import AppKit
import SwiftUI
import XCTest
@testable import ArtexCore
@testable import ArtexMac

@MainActor private final class LLMRenderingBackend: BackendJSONTransport {
    var calls = 0
    var emptyProfiles = false
    func send(method: String, path: String, body: Data?, bearer: String?) async throws -> BackendHTTPResponse {
        calls += 1
        guard method == "GET" else { return .init(status: 503, body: Data("{}".utf8)) }
        if path == "/api/llm/retry-policy" { return .init(status: 200, body: try LLMWire.encode(LLMRetryPolicy())) }
        let text: String
        if path == "/api/llm/profiles" {
            text = emptyProfiles ? "{\"profiles\":[]}" : #"{"profiles":[{"id":"7","name":"\ufeffe\u0301 中文 한국어","format":"openai","model":"fixture","is_default":true,"rate_per_second":0,"rate_per_minute":0}]}"#
        } else { text = "{\"enabled\":true,\"bind_fallback\":false,\"chain\":[]}" }
        return .init(status: 200, body: Data(text.utf8))
    }
}

final class LLMRecoveryRenderingTests: XCTestCase {
    @MainActor private func render(_ store: LLMStore) {
        for language in AppLanguage.allCases {
            for scheme in [ColorScheme.light, .dark] {
                let host = NSHostingView(rootView: LLMRecoveryView(store: store).environment(\.locale, language.locale).environment(\.colorScheme, scheme))
                for width in [440.0, 630.0, 900.0] {
                    host.frame = NSRect(x: 0, y: 0, width: width, height: 680)
                    host.layoutSubtreeIfNeeded()
                    XCTAssertNil(host.window)
                }
            }
        }
    }
    @MainActor func testOffscreenRecoveryRenderingNeverReadsWritesOrAcknowledgesAndPreservesOpaqueNames() async throws {
        let api = LLMRenderingBackend(); let store = LLMStore(service: LLMService(client: api))
        render(store); XCTAssertEqual(api.calls, 0)
        var draft = LLMProfileDraft(); draft.name = "fixture"; draft.model = "fixture"
        _ = await store.save(draft)
        let revision = try XCTUnwrap(store.unknownRevision); let failedCalls = api.calls
        render(store); XCTAssertEqual(api.calls, failedCalls); XCTAssertFalse(store.canAcknowledgeUnknown)
        for empty in [false, true] {
            api.emptyProfiles = empty; await store.load()
            let calls = api.calls; let originalName = store.profiles.first.map { Data($0.name.utf8) }
            render(store)
            XCTAssertEqual(api.calls, calls); XCTAssertEqual(store.unknownRevision, revision)
            XCTAssertTrue(store.canAcknowledgeUnknown)
            XCTAssertEqual(store.profiles.first.map { Data($0.name.utf8) }, originalName)
            if !empty { XCTAssertEqual(originalName, Data("\u{feff}e\u{301} 中文 한국어".utf8)) }
        }
        store.stop(); render(store); XCTAssertFalse(store.canAcknowledgeUnknown)
        XCTAssertEqual(store.unknownRevision, revision)
    }
}
