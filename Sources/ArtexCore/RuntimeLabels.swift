public enum RuntimeLabels {
    public static func state(_ value: LifecycleState, language: AppLanguage) -> String {
        let key: AppStringKey
        switch value {
        case .idle: key = .runtimeUIStateIdle
        case .starting: key = .runtimeUIStateStarting
        case .running: key = .runtimeUIStateRunning
        case .stopping: key = .runtimeUIStateStopping
        case .stopped: key = .runtimeUIStateStopped
        case .failed: key = .runtimeUIStateFailed
        }
        return AppStrings.text(key, language: language)
    }
    /// The diagnostic parameters may contain arbitrary paths or guest text; do not retain them in UI state.
    static func errorKey(_ error: RuntimeError) -> AppStringKey {
        switch error {
        case .invalidTransition: .runtimeUITransitionError
        case .integrity: .runtimeUIIntegrityError
        case .timeout: .runtimeUITimeoutError
        case .unsupported: .runtimeUIUnsupported
        }
    }
}
