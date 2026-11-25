import NetworkPNTRCore
import XCTest
@testable import NetworkPNTRMac

final class CompanyEditorFailureTests: XCTestCase {
    func testMissingCompanyRequiresFreshListForEveryExistingCompanyOperation() throws {
        let company = try JSONDecoder().decode(
            AssetCatalogCompany.self, from: Data(#"{"id":1,"name":"Fixture","assetCount":0}"#.utf8)
        )
        for action in [CompanyEditorAction.append(company), .replace(company), .delete(company)] {
            let failure = CompanyEditorFailure(BackendAPIError.status(404), action: action)
            XCTAssertEqual(failure, .missing)
            XCTAssertTrue(failure.requiresRefresh)
            for language in [AppLanguage.english, .japanese] {
                let message = AppStrings.text(failure.message, language: language)
                XCTAssertNotEqual(message, failure.message.rawValue)
                XCTAssertNotEqual(message, AppStrings.text(.companyUnconfirmed, language: language))
            }
        }
    }

    func testKnownInputFailuresRemainEditableAndUnknownResultsRequireRefresh() throws {
        let company = try JSONDecoder().decode(
            AssetCatalogCompany.self, from: Data(#"{"id":1,"name":"Fixture","assetCount":0}"#.utf8)
        )
        let cases: [(any Error, CompanyEditorAction, CompanyEditorFailure, Bool)] = [
            (BackendAPIError.status(409), .create, .duplicate, false),
            (BackendAPIError.status(400), .replace(company), .rejected, false),
            (AssetCatalogQueryError.invalidQuery, .create, .rejected, false),
            (BackendAPIError.status(404), .create, .unconfirmed, true),
            (BackendAPIError.status(409), .replace(company), .unconfirmed, true),
            (BackendAPIError.status(500), .replace(company), .unconfirmed, true),
        ]
        for (error, action, expected, refresh) in cases {
            let failure = CompanyEditorFailure(error, action: action)
            XCTAssertEqual(failure, expected)
            XCTAssertEqual(failure.requiresRefresh, refresh)
        }
    }
}
