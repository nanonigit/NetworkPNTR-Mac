import Foundation

/// Descriptive endpoint metadata, not a capability or network authorization.
/// Keep separate from LLMFormat, which is the existing backend wire contract.
public enum LLMEndpointIdentity: String, Equatable, Sendable {
    case openAI = "openai", anthropic, gemini, groq, custom

    static func resolve(format: LLMFormat, baseURL: String) -> Self {
        let value = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.isEmpty { return format == .anthropic ? .anthropic : .openAI }
        guard let url = URLComponents(string: value),
              url.scheme?.lowercased() == "https", url.user == nil, url.password == nil,
              url.query == nil, url.fragment == nil,
              url.percentEncodedHost?.contains("%") == false,
              url.port == nil || url.port == 443 else {
            return .custom
        }
        var path = url.percentEncodedPath
        if path.hasSuffix("/") { path.removeLast() }
        switch (format, url.host?.lowercased(), path) {
        case (.anthropic, "api.anthropic.com", ""): return .anthropic
        case (.openai, "api.openai.com", "/v1"), (.openaiResponses, "api.openai.com", "/v1"): return .openAI
        case (.openai, "generativelanguage.googleapis.com", "/v1beta/openai"): return .gemini
        case (.openai, "api.groq.com", "/openai/v1"): return .groq
        default: return .custom
        }
    }
}

extension LLMProfile {
    public var endpointIdentity: LLMEndpointIdentity {
        .resolve(format: format, baseURL: baseUrl ?? "")
    }
}

extension LLMProfileDraft {
    public var endpointIdentity: LLMEndpointIdentity {
        .resolve(format: format, baseURL: baseUrl)
    }
}
