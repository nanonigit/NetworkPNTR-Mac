import Foundation

/// Stores safe error identity so a locale change never repeats the failed operation.
public struct AppErrorMessage: Sendable {
    private enum Reason: Sendable {
        case backend(BackendAPIError), upload(ChatUploadBodyError), catalog(AppStringKey)
    }
    private let reason: Reason
    public init(_ error: any Error, fallback: AppStringKey = .errorCommunication) {
        if let error = error as? BackendAPIError { reason = .backend(error) }
        else if let error = error as? ChatUploadBodyError { reason = .upload(error) }
        else if let error = error as? RuntimeError { reason = .catalog(RuntimeLabels.errorKey(error)) }
        else { reason = .catalog(fallback) }
    }
    public init(key: AppStringKey) { reason = .catalog(key) }
    public func text(language: AppLanguage) -> String {
        switch reason {
        case let .backend(error): AppErrorText.text(error, language: language)
        case let .upload(error): AppErrorText.text(error, language: language)
        case let .catalog(key): AppStrings.text(key, language: language)
        }
    }
}
