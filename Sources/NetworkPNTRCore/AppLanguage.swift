import Foundation

public enum AppLanguage: String, Codable, CaseIterable, Identifiable, Sendable {
    case english = "en"
    case japanese = "ja"

    public var id: String { rawValue }
    public var nativeName: String { self == .english ? "English" : "日本語" }
    public var locale: Locale { Locale(identifier: rawValue) }

    public static func preferred(in identifiers: [String]) -> Self {
        for identifier in identifiers {
            let primary = identifier.split(omittingEmptySubsequences: false, whereSeparator: { $0 == "-" || $0 == "_" }).first
            if let primary, let language = Self(rawValue: primary.lowercased()) { return language }
        }
        return .english
    }
}
