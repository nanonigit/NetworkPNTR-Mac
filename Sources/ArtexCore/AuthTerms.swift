import Foundation

public enum AuthTerms {
    public static func load(language: String = "ja") throws -> [String: String] {
        guard ["ja", "en"].contains(language), let url = Bundle.module.url(forResource: "auth-terms." + language, withExtension: "json") else { throw BackendAPIError.invalidResponse }
        return try JSONDecoder().decode([String: String].self, from: Data(contentsOf: url))
    }
}
