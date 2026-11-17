import AppKit
import SwiftUI
import XCTest
@testable import NetworkPNTRCore
@testable import NetworkPNTRMac

@MainActor private final class LLMEditorRenderingBackend: BackendJSONTransport {
    var calls = 0
    func send(method: String, path: String, body: Data?, bearer: String?) async throws -> BackendHTTPResponse {
        calls += 1
        if path == "/api/llm/models" { return .init(status: 200, body: Data("{\"ok\":true,\"models\":[\"literal 中文 한국어\"]}".utf8)) }
        if path == "/api/llm/test" { return .init(status: 200, body: Data("{\"ok\":true,\"reply\":\"fixture reply\",\"model\":\"fixture\"}".utf8)) }
        return .init(status: 503, body: Data("{}".utf8))
    }
}

final class LLMEditorRenderingTests: XCTestCase {
    @MainActor private func settled(_ model: LLMEditorModel) async throws {
        for _ in 0..<2000 { if !model.isBusy { return }; try await Task.sleep(for: .milliseconds(1)) }
        XCTFail("Rendering fixture did not settle")
    }
    @MainActor func testOffscreenEditorFormatsAndLocaleChangesNeverDispatchOrNormalizeCustomDraft() {
        let api = LLMEditorRenderingBackend(); let store = LLMStore(service: LLMService(client: api))
        for editing in [false, true] {
            for format in LLMFormat.allCases {
                var draft = LLMProfileDraft(); draft.id = editing ? 7 : nil; draft.format = format
                draft.name = "\u{feff}e\u{301} 中文 한국어"; draft.model = "literal 中文 한국어"
                let model = LLMEditorModel(store: store, draft: draft)
                let originalName = Data(model.draft.name.utf8)
                for scheme in [ColorScheme.light, .dark] {
                    let host = NSHostingView(rootView: LLMProfileEditor(model: model, keyHint: editing ? "synthetic-hint" : "").environment(\.locale, AppLanguage.english.locale).environment(\.colorScheme, scheme))
                    host.frame = NSRect(x: 0, y: 0, width: 680, height: 780); host.layoutSubtreeIfNeeded()
                    host.rootView = LLMProfileEditor(model: model, keyHint: editing ? "synthetic-hint" : "").environment(\.locale, AppLanguage.japanese.locale).environment(\.colorScheme, scheme)
                    host.layoutSubtreeIfNeeded(); XCTAssertNil(host.window)
                    XCTAssertEqual(Data(model.draft.name.utf8), originalName)
                    XCTAssertEqual(model.draft.model, "literal 中文 한국어"); XCTAssertEqual(model.draft.format, format)
                }
            }
        }
        XCTAssertEqual(api.calls, 0); XCTAssertFalse(store.isMutating); XCTAssertNil(store.unknownRevision)
    }
    @MainActor func testNewProfileChoicesRenderFreshDraftsInBothLanguages() {
        let api = LLMEditorRenderingBackend()
        let store = LLMStore(service: LLMService(client: api))
        let providers: [LLMCloudProvider?] = LLMCloudProvider.allCases.map(Optional.some) + [nil]
        var ids = Set<UUID>()
        for provider in providers {
            let context = LLMEditorContext.newProfile(provider: provider)
            XCTAssertTrue(ids.insert(context.id).inserted)
            XCTAssertNil(context.draft.id)
            XCTAssertTrue(context.keyHint.isEmpty)
            XCTAssertTrue(context.draft.apiKey.isEmpty)
            XCTAssertTrue(context.draft.model.isEmpty)
            XCTAssertTrue(context.draft.name.isEmpty)
            if let provider {
                XCTAssertEqual(context.draft.endpointIdentity.rawValue, provider.rawValue)
            } else {
                XCTAssertEqual(context.draft.baseUrl, "")
                XCTAssertEqual(context.draft.format, LLMProfileDraft().format)
            }
            let model = LLMEditorModel(store: store, draft: context.draft)
            for language in [AppLanguage.english, .japanese] {
                let host = NSHostingView(rootView: LLMProfileEditor(model: model, keyHint: context.keyHint)
                    .environment(\.locale, language.locale))
                host.frame = NSRect(x: 0, y: 0, width: 680, height: 780)
                host.layoutSubtreeIfNeeded()
                XCTAssertNil(host.window)
                XCTAssertEqual(model.draft.baseUrl, context.draft.baseUrl)
                XCTAssertEqual(model.draft.format, context.draft.format)
            }
            model.draft.apiKey = "synthetic-only"
            model.close()
            XCTAssertTrue(model.draft.apiKey.isEmpty)
        }
        XCTAssertEqual(api.calls, 0)
    }

    @MainActor func testRenderingCandidatesProbeAndFailureStatesDoesNotRepeatExplicitActions() async throws {
        let api = LLMEditorRenderingBackend(); let store = LLMStore(service: LLMService(client: api))
        for state in 0..<3 {
            var draft = LLMProfileDraft(); draft.name = "fixture"; draft.model = "fixture"
            let model = LLMEditorModel(store: store, draft: draft)
            if state == 0 { XCTAssertTrue(model.fetchModels()) }
            else if state == 1 { XCTAssertTrue(model.testConnection()) }
            else { XCTAssertTrue(model.save()) }
            try await settled(model)
            let before = api.calls
            let host = NSHostingView(rootView: LLMProfileEditor(model: model, keyHint: "").environment(\.locale, AppLanguage.japanese.locale))
            host.frame = NSRect(x: 0, y: 0, width: 680, height: 780); host.layoutSubtreeIfNeeded()
            XCTAssertNil(host.window); XCTAssertEqual(api.calls, before)
            if state == 2 { XCTAssertNotNil(store.unknownRevision) }
        }
        XCTAssertEqual(api.calls, 3)
    }
}
