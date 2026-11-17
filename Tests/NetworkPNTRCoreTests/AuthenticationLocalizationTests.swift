import XCTest
@testable import NetworkPNTRCore

final class AuthenticationLocalizationTests: XCTestCase {
    func testNativeAuthenticationLabelsResolveBothLanguages() {
        for (key,en,ja) in [
            (AppStringKey.authChecking,"Checking authentication status","認証状態を確認しています"),
            (.authUnavailable,"Unable to confirm authentication status","認証状態を確認できません"),
            (.authRecovery,"Try again after the database or connection recovers.","データベースまたは通信の復旧後に再試行してください。"),
            (.authRetry,"Retry","再試行"),
            (.authLoggedIn,"Logged in","ログイン済み"),
            (.authConnected,"Connected to NetworkPNTR in the dedicated VM. Features are being migrated after comparison testing.","専用VMのNetworkPNTRに接続しています。各機能は比較テストを通したものから順に移植します。"),
            (.authLogout,"Log out","ログアウト"),
            (.authSetupTitle,"Set administrator password","管理者パスワードを設定"),
            (.authLogin,"Log in","ログイン"),
            (.authSetupHelp,"Set a password for this Mac’s dedicated NetworkPNTR environment. The app securely passes the setup token.","このMacの専用NetworkPNTR環境にパスワードを設定します。初期設定トークンはアプリが安全に受け渡します。"),
            (.authLoginHelp,"The username is NetworkPNTR. Enter your configured password.","ユーザー名はNetworkPNTRです。設定したパスワードを入力してください。"),
            (.authUsername,"Username","ユーザー名"),
            (.authNewPassword,"New password","新しいパスワード"),
            (.authPassword,"Password","パスワード"),
            (.authPasswordHint,"At least 8 characters, at most 72 UTF-8 bytes","8文字以上、UTF-8で72バイト以内"),
            (.authConfirm,"Confirm password","パスワードを確認"),
            (.authRepeat,"Re-enter password","もう一度入力"),
            (.authAgree,"I agree to the terms of use","利用条件に同意する"),
            (.authReadTerms,"Read terms of use","利用条件を読む"),
            (.authSetPassword,"Set password","パスワードを設定"),
            (.authTermsTitle,"Terms of use","利用条件"),
            (.authAcceptTerms,"Agree","同意する"),
            (.authTermsUnavailable,"Could not load the terms of use. Close this window and try again.","利用条件を読み込めませんでした。閉じてから、もう一度お試しください。")
        ] {
            XCTAssertEqual(AppStrings.text(key,language:.english),en)
            XCTAssertEqual(AppStrings.text(key,language:.japanese),ja)
        }
    }
    func testBothCompleteTermsDocumentsMatchPinnedBrowserWithoutRewriting() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource:"auth-terms-localization",withExtension:"json",subdirectory:"Fixtures"))
        struct Fixture:Decodable {let baseline:String;let documents:[String:[String:String]]}
        let fixture = try JSONDecoder().decode(Fixture.self,from:Data(contentsOf:url))
        XCTAssertEqual(fixture.baseline,"e75ae371ad777ffd1eecdd28d2781a6519b05591")
        let documents = try AuthTerms.loadAll()
        XCTAssertEqual(Set(documents.keys),Set(AppLanguage.allCases))
        for language in AppLanguage.allCases {
            let terms = try XCTUnwrap(documents[language])
            XCTAssertEqual(terms.count,28);XCTAssertTrue(terms.values.allSatisfy{!$0.isEmpty})
            XCTAssertEqual(terms,fixture.documents[language.rawValue])
        }
    }
    func testLegacyTermsLoaderAndUnsupportedLanguages() throws {
        XCTAssertEqual(try AuthTerms.load(),try AuthTerms.load(language:"ja"))
        for unsupported in ["zh","ko","en-US","","../en"] {XCTAssertThrowsError(try AuthTerms.load(language:unsupported))}
    }
    func testReadGateIgnoresEmptyGeometryAndKeepsPerOpenLatchAcrossLocale() {
        var progress = AuthTermsReadingProgress()
        progress.observe(.init(documentLoaded: false, atEnd: true))
        XCTAssertFalse(progress.hasReadToEnd)
        XCTAssertFalse(progress.canAgree(documentLoaded: false))
        XCTAssertFalse(progress.canAgree(documentLoaded: true))
        progress.observe(.init(documentLoaded: true, atEnd: false))
        XCTAssertFalse(progress.canAgree(documentLoaded: true))
        progress.observe(.init(documentLoaded: true, atEnd: true))
        XCTAssertTrue(progress.canAgree(documentLoaded: true))
        // A locale change can make the translated document taller; preserve the per-open latch.
        progress.observe(.init(documentLoaded: true, atEnd: false))
        XCTAssertTrue(progress.canAgree(documentLoaded: true))
        XCTAssertFalse(progress.canAgree(documentLoaded: false))
        XCTAssertFalse(AuthTermsReadingProgress().hasReadToEnd)
    }
    func testLoadedShortDocumentChangesObservationEvenWhenAtEndStaysTrue() {
        let empty = AuthTermsViewport(documentLoaded: false, atEnd: true)
        let short = AuthTermsViewport(documentLoaded: true, atEnd: true)
        XCTAssertNotEqual(empty,short)
        var progress = AuthTermsReadingProgress()
        progress.observe(empty);XCTAssertFalse(progress.hasReadToEnd)
        progress.observe(short);XCTAssertTrue(progress.canAgree(documentLoaded: true))
    }
}
