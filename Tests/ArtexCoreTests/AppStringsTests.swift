import XCTest
@testable import ArtexCore

final class AppStringsTests: XCTestCase {
    func testCompiledCatalogResolvesBothLanguagesForEveryShellKey() throws {
        for key in AppStringKey.allCases {
            for language in AppLanguage.allCases {
                let value = AppStrings.text(key, language: language)
                XCTAssertFalse(value.isEmpty)
                XCTAssertNotEqual(value, key.rawValue)
                XCTAssertFalse(value.unicodeScalars.contains { (0xAC00...0xD7AF).contains($0.value) })
            }
        }
        XCTAssertEqual(AppStrings.text(.runtime, language: .english), "Runtime")
        XCTAssertEqual(AppStrings.text(.runtime, language: .japanese), "実行環境")
        XCTAssertEqual(AppStrings.text(.language, language: .english), "Language")
        XCTAssertEqual(AppStrings.text(.language, language: .japanese), "言語")
    }
    func testFeatureTitlesCoverEntirePinnedCatalogAndPreserveUnknownContent() throws {
        let catalog = try FeatureCatalog.load()
        XCTAssertEqual(catalog.features.count, 21)
        for feature in catalog.features {
            XCTAssertNotNil(AppStrings.featureKey(feature.id))
            XCTAssertFalse(AppStrings.featureTitle(feature.id, fallback: "UNTRANSLATED", language: .japanese).contains("UNTRANSLATED"))
        }
        XCTAssertEqual(AppStrings.featureTitle("chat", fallback: "original", language: .english), "Chat")
        XCTAssertEqual(AppStrings.featureTitle("chat", fallback: "original", language: .japanese), "チャット")
        XCTAssertEqual(AppStrings.featureTitle("custom", fallback: "自定义 사용자 **literal**", language: .japanese), "自定义 사용자 **literal**")
    }
    func testPlannedFeatureKeepsVariableContentLiteralInBothLanguages() {
        for language in AppLanguage.allCases {
            let value = AppStrings.plannedFeature(phase: 4, path: "/fixture/%@/中文/한국어", language: language)
            XCTAssertTrue(value.contains("4"))
            XCTAssertTrue(value.contains("/fixture/%@/中文/한국어"))
        }
    }
    func testMissingJapaneseEntryFallsBackToEnglishAndUnknownKeyRemainsVisible() {
        XCTAssertEqual(AppStrings.lookup("shell.productName", language: .japanese), "ARTEX")
        XCTAssertEqual(AppStrings.lookup("missing.fixture.key", language: .japanese), "missing.fixture.key")
    }
}
