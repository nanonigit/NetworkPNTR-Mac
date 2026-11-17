import XCTest
@testable import NetworkPNTRCore

final class LLMModelTests: XCTestCase {
    func testDraftSendsEveryBrowserFieldAndPreservesBlankKeyUpdate() throws {
        var draft = LLMProfileDraft()
        draft.id = 7; draft.name = " fixture "; draft.model = " model "; draft.format = .openai
        draft.maxTokensField = "max_completion_tokens"; draft.apiKey = ""
        draft.ratePerSecond = 1.5; draft.ratePerMinute = 30; draft.contextWindowK = 64
        draft.priority = 3; draft.poolExclude = true; draft.streaming = false; draft.maxTokens = 256
        draft.thinkingType = "enabled"; draft.reasoningEffort = "high"
        draft.sessionHeaderKey = "X-Session-Id"; draft.retry.connect.attempts = -1
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: draft.encoded()) as? [String: Any])
        XCTAssertEqual(object["id"] as? Int, 7)
        XCTAssertEqual(object["name"] as? String, "fixture")
        XCTAssertEqual(object["model"] as? String, "model")
        XCTAssertEqual(object["api_key"] as? String, "")
        XCTAssertEqual(object["streaming"] as? Bool, false)
        XCTAssertEqual(object["max_tokens_field"] as? String, "max_completion_tokens")
        XCTAssertEqual(Set(object.keys), Set(["id", "name", "format", "model", "base_url", "proxy", "api_key", "rate_per_second", "rate_per_minute", "context_window_k", "priority", "pool_exclude", "streaming", "max_tokens", "max_tokens_field", "thinking_type", "reasoning_effort", "session_header_key", "retry"]))
        for format in [LLMFormat.anthropic, .openaiResponses] {
            draft.format = format
            let encoded = try XCTUnwrap(JSONSerialization.jsonObject(with: draft.encoded()) as? [String: Any])
            XCTAssertEqual(encoded["max_tokens_field"] as? String, "")
        }
    }
    func testInputValidationAndCredentialRedaction() throws {
        var draft = LLMProfileDraft()
        XCTAssertThrowsError(try draft.encoded())
        draft.name = "valid"; draft.model = "valid"; draft.apiKey = "sensitive-fixture"
        XCTAssertFalse(String(describing: draft).contains(draft.apiKey))
        draft.sessionHeaderKey = "X-Test\r\nInjected"
        XCTAssertThrowsError(try draft.encoded())
        draft.sessionHeaderKey = "X-Test"
        draft.ratePerSecond = .infinity
        XCTAssertThrowsError(try draft.encoded())
        draft.ratePerSecond = 0; draft.contextWindowK = 1001
        XCTAssertThrowsError(try draft.encoded())
        draft.contextWindowK = 0; draft.id = -1
        XCTAssertThrowsError(try draft.encoded())
    }
    func testResponseContainsHintOnlyAndEditorDoesNotRepopulateKey() throws {
        let wire = Data(#"{"id":"7","name":"fixture","format":"openai-responses","model":"model","is_default":false,"rate_per_second":0,"rate_per_minute":0,"api_key_hint":"masked","api_key":"must-never-enter-response-model"}"#.utf8)
        let profile = try LLMWire.decode(LLMProfile.self, from: wire)
        XCTAssertEqual(profile.id, "7")
        XCTAssertEqual(profile.apiKeyHint, "masked")
        let draft = try LLMProfileDraft(profile: profile)
        XCTAssertEqual(draft.apiKey, "")
        XCTAssertEqual(draft.id, 7)
        XCTAssertTrue(draft.streaming)
        XCTAssertFalse(String(describing: profile).contains("must-never-enter-response-model"))
    }
    func testRetryRulesUseBackendBoundsAndZeroInheritance() {
        XCTAssertEqual(LLMRetryRule().attempts, 0)
        XCTAssertEqual(LLMRetryRule(attempts: -20, intervalMs: -1).clamped(), LLMRetryRule(attempts: -1, intervalMs: 0))
        XCTAssertEqual(LLMRetryRule(attempts: 99, intervalMs: 4_000_000).clamped(), LLMRetryRule(attempts: 20, intervalMs: 3_600_000))
    }
}
