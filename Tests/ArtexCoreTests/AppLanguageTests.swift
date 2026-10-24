import Foundation
import XCTest
@testable import ArtexCore

final class AppLanguageTests: XCTestCase {
    func testOnlyEnglishAndJapaneseAreValidWireValues() throws {
        XCTAssertEqual(AppLanguage.allCases.map(\.rawValue), ["en", "ja"])
        XCTAssertEqual(AppLanguage.english.id, "en")
        XCTAssertEqual(AppLanguage.japanese.id, "ja")
        XCTAssertEqual(AppLanguage.english.nativeName, "English")
        XCTAssertEqual(AppLanguage.japanese.nativeName, "日本語")
        XCTAssertEqual(AppLanguage.japanese.locale.identifier, "ja")
        XCTAssertEqual(AppLanguage.english.locale.identifier, "en")
        for language in AppLanguage.allCases {
            XCTAssertEqual(try JSONDecoder().decode(AppLanguage.self, from: JSONEncoder().encode(language)), language)
        }
        for value in ["ko", "zh", "es", "", "JA", "ja-JP"] {
            XCTAssertNil(AppLanguage(rawValue: value))
            XCTAssertThrowsError(try JSONDecoder().decode(AppLanguage.self, from: JSONEncoder().encode(value)))
        }
    }
    func testSystemPreferenceOrderAndRegionalForms() {
        for (preferences, expected) in [
            (["fr-FR", "ja-JP", "en-US"], AppLanguage.japanese),
            (["EN_us", "ja"], .english), (["zh-Hant", "ko-KR"], .english),
            (["ja_JP"], .japanese), ([], .english), (["-ja", "japanese", "jafoo"], .english)
        ] {
            XCTAssertEqual(AppLanguage.preferred(in: preferences), expected)
        }
    }
    @MainActor func testFreshChoiceIsSavedAndExplicitSwitchSurvivesNewInstances() throws {
        let suite = "artex-language-test-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("preserve", forKey: "unrelated")
        let first = AppLanguagePreferences(defaults: defaults, preferredLanguages: ["ja-JP"])
        XCTAssertEqual(first.language, .japanese)
        XCTAssertEqual(defaults.string(forKey: AppLanguagePreferences.key), "ja")
        first.select(.english)
        XCTAssertEqual(first.language, .english)
        let reopened = AppLanguagePreferences(defaults: defaults, preferredLanguages: ["ja"])
        XCTAssertEqual(reopened.language, .english)
        reopened.select(.japanese)
        XCTAssertEqual(AppLanguagePreferences(defaults: defaults, preferredLanguages: ["en"]).language, .japanese)
        XCTAssertEqual(defaults.string(forKey: "unrelated"), "preserve")
        XCTAssertEqual(defaults.persistentDomain(forName: suite)?.count, 2)
    }
    @MainActor func testInvalidStoredChoiceFallsBackToEnglishInsteadOfSystemLanguage() throws {
        let suite = "artex-language-test-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        for value in ["ko", "zh", "ja-JP", "JA", "", " en ", 42, ["ja"]] as [Any] {
            defaults.set(value, forKey: AppLanguagePreferences.key)
            let preference = AppLanguagePreferences(defaults: defaults, preferredLanguages: ["ja"])
            XCTAssertEqual(preference.language, .english)
            XCTAssertEqual(defaults.string(forKey: AppLanguagePreferences.key), "en")
        }
    }
    @MainActor func testSeparateSuitesDoNotShareSelection() throws {
        let a = "artex-language-test-" + UUID().uuidString, b = "artex-language-test-" + UUID().uuidString
        let one = try XCTUnwrap(UserDefaults(suiteName: a)), two = try XCTUnwrap(UserDefaults(suiteName: b))
        defer { one.removePersistentDomain(forName: a); two.removePersistentDomain(forName: b) }
        let first = AppLanguagePreferences(defaults: one, preferredLanguages: ["ja"])
        let second = AppLanguagePreferences(defaults: two, preferredLanguages: ["en"])
        first.select(.japanese)
        XCTAssertEqual(second.language, .english)
        XCTAssertEqual(two.string(forKey: AppLanguagePreferences.key), "en")
    }
}
