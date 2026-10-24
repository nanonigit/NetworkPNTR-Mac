import XCTest
@testable import ArtexCore

final class ErrorLocalizationTests: XCTestCase {
    func testKnownStatusAndNumericDiagnosticsInBothLanguages() {
        for (code, en, ja) in [
            (401, "The username or password is incorrect.", "ユーザー名またはパスワードが正しくありません。"),
            (403, "This operation is not allowed. Check the initial setup state.", "この操作は許可されていません。初期設定の状態を確認してください。"),
            (429, "Too many attempts. Wait a while and try again.", "試行回数が多いため、しばらく待ってから再試行してください。"),
            (503, "The database is unavailable. Try again after recovery.", "データベースを利用できません。復旧後に再試行してください。"),
            (409, "Communication with the runtime failed (HTTP 409).", "実行環境との通信に失敗しました（HTTP 409）。")
        ] {
            XCTAssertEqual(AppErrorText.text(BackendAPIError.status(code), language: .english), en)
            XCTAssertEqual(AppErrorText.text(BackendAPIError.status(code), language: .japanese), ja)
            XCTAssertEqual(BackendAPIError.status(code).localizedDescription, ja)
        }
        XCTAssertEqual(AppErrorText.text(BackendAPIError.secureStorage(-25300), language: .english), "Keychain operation failed (-25300).")
        XCTAssertEqual(AppErrorText.text(BackendAPIError.secureStorage(-25300), language: .japanese), "Keychainの操作に失敗しました（-25300）。")
        XCTAssertEqual(AppErrorText.text(BackendAPIError.invalidResponse, language: .english), "The runtime response could not be verified.")
    }

    func testEveryTypedValidationHasDistinctBilingualCatalogText() {
        XCTAssertEqual(BackendValidation.allCases.count, 16)
        for reason in BackendValidation.allCases {
            let error = BackendAPIError.validation(reason)
            let en = AppErrorText.text(error, language: .english)
            let ja = AppErrorText.text(error, language: .japanese)
            XCTAssertFalse(en.isEmpty); XCTAssertFalse(en.hasPrefix("error."))
            XCTAssertFalse(ja.isEmpty); XCTAssertFalse(ja.hasPrefix("error."))
            XCTAssertNotEqual(en, ja)
            XCTAssertEqual(error.localizedDescription, ja)
        }
        XCTAssertEqual(AppErrorText.text(BackendAPIError.validation(.missingProvider), language: .english), "No LLM configuration exists. Add a provider under System → LLM settings.")
        XCTAssertEqual(AppErrorText.text(BackendAPIError.validation(.missingProvider), language: .japanese), "LLM設定がありません。システムのLLM設定で接続先を追加してください。")
    }

    func testUploadErrorsAndUnknownFailuresDoNotExposeSensitiveDetails() {
        for error in [ChatUploadBodyError.invalidFile, .invalidFraming, .tooLarge, .changedFile, .readFailure] {
            let en = AppErrorText.text(error, language: .english)
            let ja = AppErrorText.text(error, language: .japanese)
            XCTAssertFalse(en.hasPrefix("error.")); XCTAssertNotEqual(en, ja)
            XCTAssertEqual(error.localizedDescription, ja)
        }
        let privateError = NSError(domain: "private-secret", code: 1, userInfo: [NSLocalizedDescriptionKey: "private-secret /Users/private/token"])
        XCTAssertEqual(AppErrorText.text(privateError, language: .english), "Check communication with the runtime.")
        XCTAssertEqual(AppErrorText.text(privateError, language: .japanese), "実行環境との通信を確認してください。")
    }
}
