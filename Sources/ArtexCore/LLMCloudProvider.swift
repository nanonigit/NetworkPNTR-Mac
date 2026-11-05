import Foundation

/// New-profile presets only. A preset is not proof of model or tool support.
public enum LLMCloudProvider: String, CaseIterable, Sendable {
    case openAI = "openai", anthropic, gemini, groq
}

extension LLMProfileDraft {
    /// Start from defaults so switching vendors never inherits a stored key or ID.
    /// Concrete endpoint/format fields use the existing guest persistence contract.
    public init(provider: LLMCloudProvider) {
        self.init()
        switch provider {
        case .openAI:
            format = .openai; baseUrl = "https://api.openai.com/v1"
        case .anthropic:
            format = .anthropic; baseUrl = "https://api.anthropic.com"
        case .gemini:
            format = .openai; baseUrl = "https://generativelanguage.googleapis.com/v1beta/openai/"
        case .groq:
            format = .openai; baseUrl = "https://api.groq.com/openai/v1"
        }
    }
}
