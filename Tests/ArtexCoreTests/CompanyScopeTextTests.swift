import Foundation
import XCTest
@testable import ArtexCore

final class CompanyScopeTextTests: XCTestCase {
    func testDetectsBrowserRuleKindsAndReportsOriginalLineNumbers() {
        let input = """
        example.test
        https://192.0.2.4/path
        2001:db8::/32

        192.0.2.0/8
        999.0.0.1
        ICP 登録
        Fixture Company
        """
        let parsed = CompanyScopeText(input.replacingOccurrences(of: "\n", with: "\r\n"))
        XCTAssertEqual(parsed.rules.map(\.kind), [.domain, .ip, .cidr, .icp, .keyword])
        XCTAssertEqual(parsed.rules[1].value, "192.0.2.4")
        XCTAssertEqual(parsed.invalidLines, [5, 6])
    }

    func testPreservesSavedKindsForIdenticalLookingRulesInOrder() throws {
        let saved = try JSONDecoder().decode([AssetCatalogCompany.ScopeRule].self, from: Data(
            #"[{"raw":"example.test","kind":"keyword"},{"raw":"example.test","kind":"domain"}]"#.utf8
        ))
        let parsed = CompanyScopeText("example.test\nexample.test\nexample.test", preserving: saved)
        XCTAssertEqual(parsed.rules.map(\.kind), [.keyword, .domain, .domain])
        XCTAssertTrue(parsed.invalidLines.isEmpty)
        XCTAssertTrue(CompanyScopeText("  \n").rules.isEmpty)
    }
}
