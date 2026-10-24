import Foundation
import Observation

/// Owns only the application language preference; never backend or credential state.
@MainActor @Observable public final class AppLanguagePreferences {
    public static let key = "artex.applicationLanguage"
    public private(set) var language: AppLanguage
    @ObservationIgnored private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard, preferredLanguages: [String] = Locale.preferredLanguages) {
        self.defaults = defaults
        if let saved = defaults.object(forKey: Self.key) {
            language = (saved as? String).flatMap(AppLanguage.init(rawValue:)) ?? .english
        } else {
            language = AppLanguage.preferred(in: preferredLanguages)
        }
        defaults.set(language.rawValue, forKey: Self.key)
    }

    public func select(_ language: AppLanguage) {
        defaults.set(language.rawValue, forKey: Self.key)
        self.language = language
    }
}
