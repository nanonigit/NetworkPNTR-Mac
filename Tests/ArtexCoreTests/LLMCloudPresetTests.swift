import XCTest
@testable import ArtexCore

@MainActor private final class CloudPresetTransport: BackendJSONTransport {
    var calls: [(String, String, Data?)] = []
    var responses: [BackendHTTPResponse] = []
    func enqueue(_ object: [String: Any]) throws {
        responses.append(.init(status: 200, body: try JSONSerialization.data(withJSONObject: object)))
    }
    func send(method: String, path: String, body: Data?, bearer: String?) async throws -> BackendHTTPResponse {
        XCTAssertNil(bearer)
        calls.append((method, path, body))
        guard !responses.isEmpty else { throw BackendAPIError.invalidResponse }
        return responses.removeFirst()
    }
}

final class LLMCloudPresetTests: XCTestCase {
    func testAllFourPresetsCreateIndependentUnconfiguredProfiles() throws {
        XCTAssertEqual(LLMCloudProvider.allCases.count, 4)
        for provider in LLMCloudProvider.allCases {
            var first = LLMProfileDraft(provider: provider)
            XCTAssertEqual(first.endpointIdentity.rawValue, provider.rawValue)
            XCTAssertEqual(first.format, provider == .anthropic ? .anthropic : .openai)
            XCTAssertNil(first.id)
            XCTAssertEqual(first.apiKey, ""); XCTAssertEqual(first.proxy, "")
            XCTAssertEqual(first.model, ""); XCTAssertEqual(first.name, "")
            XCTAssertEqual(first.sessionHeaderKey, ""); XCTAssertEqual(first.reasoningEffort, "")
            XCTAssertEqual(first.thinkingType, ""); XCTAssertEqual(first.maxTokens, 0)
            XCTAssertEqual(first.maxTokensField, ""); XCTAssertEqual(first.retry, LLMRetryOverride())
            XCTAssertTrue(first.streaming)
            XCTAssertThrowsError(try first.encoded(), "A preset must not silently select a model")
            first.id = 42; first.apiKey = "synthetic-only"; first.model = "opaque"
            let second = LLMProfileDraft(provider: provider)
            XCTAssertNil(second.id); XCTAssertEqual(second.apiKey, ""); XCTAssertEqual(second.model, "")
        }
    }

    @MainActor func testPresetsUseExistingSaveDiscoveryAndLoadContracts() async throws {
        let expected: [(LLMCloudProvider, String)] = [
            (.openAI, "https://api.openai.com/v1"),
            (.anthropic, "https://api.anthropic.com"),
            (.gemini, "https://generativelanguage.googleapis.com/v1beta/openai/"),
            (.groq, "https://api.groq.com/openai/v1")
        ]
        for (provider, endpoint) in expected {
            let api = CloudPresetTransport(); let service = LLMService(client: api)
            var draft = LLMProfileDraft(provider: provider)
            draft.name = "fixture"; draft.model = "opaque-model"; draft.apiKey = "synthetic-\(provider.rawValue)"
            try api.enqueue(["id": 7]); let id = try await service.save(draft)
            XCTAssertEqual(id, 7)
            XCTAssertEqual(api.calls.last?.0, "POST"); XCTAssertEqual(api.calls.last?.1, "/api/llm/profiles")
            let saved = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(api.calls.last?.2)) as? [String: Any])
            XCTAssertEqual(saved["base_url"] as? String, endpoint)
            XCTAssertEqual(saved["format"] as? String, provider == .anthropic ? "anthropic" : "openai")
            XCTAssertEqual(saved["api_key"] as? String, draft.apiKey)
            XCTAssertNil(saved["id"]); XCTAssertNil(saved["provider"])
            try api.enqueue(["ok": true, "models": ["opaque-model"]])
            let models = try await service.models(draft)
            XCTAssertEqual(models, ["opaque-model"])
            let discovery = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(api.calls.last?.2)) as? [String: Any])
            XCTAssertEqual(api.calls.last?.1, "/api/llm/models")
            XCTAssertEqual(discovery["provider"] as? String, provider == .anthropic ? "anthropic" : "openai")
            XCTAssertEqual(discovery["base_url"] as? String, endpoint)
            XCTAssertEqual(discovery["api_key"] as? String, draft.apiKey)
            XCTAssertNil(discovery["profile_id"])
            var response = saved
            response.removeValue(forKey: "api_key")
            response["id"] = "7"; response["is_default"] = false; response["api_key_hint"] = "masked"
            try api.enqueue(["profiles": [response]])
            let profiles = try await service.profiles()
            let profile = try XCTUnwrap(profiles.first)
            XCTAssertEqual(profile.endpointIdentity.rawValue, provider.rawValue)
            let restored = try LLMProfileDraft(profile: profile)
            XCTAssertEqual(restored.id, 7); XCTAssertEqual(restored.baseUrl, endpoint)
            XCTAssertEqual(restored.apiKey, ""); XCTAssertEqual(restored.model, "opaque-model")
        }
    }
}
