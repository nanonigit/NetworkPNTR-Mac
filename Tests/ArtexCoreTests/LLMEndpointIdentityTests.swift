import XCTest
@testable import ArtexCore

final class LLMEndpointIdentityTests: XCTestCase {
    func testDefaultsAndOfficialCompatibleEndpoints() {
        let cases: [(LLMFormat, String, LLMEndpointIdentity)] = [
            (.anthropic, "", .anthropic), (.openai, "  \n", .openAI),
            (.openaiResponses, "", .openAI),
            (.anthropic, "https://api.anthropic.com/", .anthropic),
            (.openaiResponses, "https://api.openai.com/v1/", .openAI),
            (.openai, "https://generativelanguage.googleapis.com/v1beta/openai/", .gemini),
            (.openai, "https://api.groq.com/openai/v1", .groq),
            (.openai, " https://API.GROQ.COM:443/openai/v1/\n", .groq)
        ]
        for (format, endpoint, expected) in cases {
            var draft = LLMProfileDraft()
            draft.format = format; draft.baseUrl = endpoint
            XCTAssertEqual(draft.endpointIdentity, expected, endpoint)
            XCTAssertEqual(draft.baseUrl, endpoint)
        }
    }

    func testCustomEndpointsAndMismatchedFormatsAreNeverRelabeled() {
        let endpoints = [
            "https://%61pi.groq.com/openai/v1", "https://api%2Egroq.com/openai/v1",
            "http://api.groq.com/openai/v1", "https://api.groq.com:8443/openai/v1",
            "https://api.groq.com.evil.invalid/openai/v1", "https://gateway.invalid/openai/v1",
            "https://api.groq.com/openai/v1?key=opaque", "https://api.groq.com/openai/v1#fragment",
            "https://user@api.groq.com/openai/v1", "https://api.groq.com/openai/v1/chat/completions",
            "https://api.groq.com/openai/%761", "https://api.groq.com/openai/v1//",
            "https://api.groq.com", "not a URL", "https://generativelanguage.googleapis.com/v1beta",
            "https://api.groq.com/openai/v1?", "https://api.groq.com/openai/v1#"
        ]
        for endpoint in endpoints {
            var draft = LLMProfileDraft(); draft.format = .openai; draft.baseUrl = endpoint
            XCTAssertEqual(draft.endpointIdentity, .custom, endpoint)
        }
        for format in [LLMFormat.anthropic, .openaiResponses] {
            var draft = LLMProfileDraft(); draft.format = format
            draft.baseUrl = "https://api.groq.com/openai/v1"
            XCTAssertEqual(draft.endpointIdentity, .custom)
        }
        var draft = LLMProfileDraft(); draft.format = .openai
        draft.baseUrl = "https://api.anthropic.com"
        XCTAssertEqual(draft.endpointIdentity, .custom)
    }

    func testExistingProfileRoundTripKeepsWireFormatAndDoesNotPersistDerivedIdentity() throws {
        for (url, expected) in [
            ("https://api.groq.com/openai/v1", LLMEndpointIdentity.groq),
            ("https://generativelanguage.googleapis.com/v1beta/openai/", .gemini),
            ("https://custom.invalid/v1", .custom)
        ] {
            let wire = try JSONSerialization.data(withJSONObject: [
                "id": "7", "name": "opaque", "format": "openai", "model": "opaque-model",
                "is_default": false, "rate_per_second": 0, "rate_per_minute": 0,
                "base_url": url, "api_key_hint": "masked"
            ])
            let profile = try LLMWire.decode(LLMProfile.self, from: wire)
            XCTAssertEqual(profile.endpointIdentity, expected)
            let draft = try LLMProfileDraft(profile: profile)
            XCTAssertEqual(draft.endpointIdentity, expected)
            XCTAssertEqual(draft.apiKey, "")
            let object = try XCTUnwrap(JSONSerialization.jsonObject(with: draft.encoded()) as? [String: Any])
            XCTAssertEqual(object["format"] as? String, "openai")
            XCTAssertEqual(object["base_url"] as? String, url)
            XCTAssertNil(object["endpoint_identity"])
            XCTAssertNil(object["provider"])
        }
        XCTAssertEqual(LLMFormat.allCases.map(\.rawValue), ["anthropic", "openai", "openai-responses"])
    }
}
