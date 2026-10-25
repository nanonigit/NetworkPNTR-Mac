import Foundation

/// Native-owned validation identity; never constructed from backend error text.
public enum BackendValidation: String, CaseIterable, Sendable {
    case activeProfile
    case modelList
    case testModel
    case connectionTest
    case missingProvider
    case conversationInput
    case messageRequired
    case passwordMismatch
    case passwordShort
    case passwordBytes
    case termsRequired
    case passwordRequired
    case mentionQuery
    case modelRequired
    case modelLimits
    case sessionHeader
}

/// Explicit-language presentation. Unknown errors never expose their descriptions.
public enum AppErrorText {
    public static func text(_ error: any Error, language: AppLanguage) -> String {
        func s(_ key: AppStringKey) -> String { AppStrings.text(key, language: language) }
        if let error = error as? TaskTemplateInputError { return s(error.key) }
        if let error = error as? TaskInputError { return s(error.key) }
        if let error = error as? RuntimeError { return s(RuntimeLabels.errorKey(error)) }
        if let error = error as? BackendAPIError {
            switch error {
            case .status(401): return s(.errorCredentials)
            case .status(403): return s(.errorForbidden)
            case .status(429): return s(.errorRateLimited)
            case .status(503): return s(.errorDatabaseUnavailable)
            case let .status(code): return s(.errorHttpStatus).replacingOccurrences(of: "{code}", with: String(code))
            case .invalidResponse: return s(.errorInvalidResponse)
            case let .secureStorage(code): return s(.errorKeychain).replacingOccurrences(of: "{code}", with: String(code))
            case let .validation(reason): return AppStrings.lookup("error.validation." + reason.rawValue, language: language)
            }
        }
        if let error = error as? ChatUploadBodyError {
            switch error {
            case .invalidFile: return s(.errorUploadInvalidFile)
            case .invalidFraming: return s(.errorUploadInvalidFraming)
            case .tooLarge: return s(.errorUploadTooLarge)
            case .changedFile: return s(.errorUploadChangedFile)
            case .readFailure: return s(.errorUploadReadFailure)
            }
        }
        return s(.errorCommunication)
    }
}
