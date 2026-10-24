import Foundation

public enum AuthTerms {
    /// Preload only bundled supported documents; switching locale does not reload the sheet.
    public static func loadAll() throws -> [AppLanguage: [String: String]] {
        try Dictionary(uniqueKeysWithValues: AppLanguage.allCases.map { language in
            (language, try load(language: language.rawValue))
        })
    }

    public static func load(language: String = "ja") throws -> [String: String] {
        guard ["ja", "en"].contains(language), let url = Bundle.module.url(forResource: "auth-terms." + language, withExtension: "json") else { throw BackendAPIError.invalidResponse }
        return try JSONDecoder().decode([String: String].self, from: Data(contentsOf: url))
    }
}
