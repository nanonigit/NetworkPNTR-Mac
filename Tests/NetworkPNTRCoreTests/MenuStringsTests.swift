import XCTest
@testable import NetworkPNTRCore
final class MenuStringsTests:XCTestCase {
    func testMenuCatalogAndOpaqueApplicationName() throws {
        struct Fixture:Decodable {struct Entry:Decodable {let key:String;let en:String;let ja:String};let entries:[Entry]}
        let url=try XCTUnwrap(Bundle.module.url(forResource:"menu-localization",withExtension:"json",subdirectory:"Fixtures"))
        let f=try JSONDecoder().decode(Fixture.self,from:Data(contentsOf:url));XCTAssertEqual(f.entries.count,28)
        for e in f.entries {let key=try XCTUnwrap(AppStringKey(rawValue:e.key));XCTAssertEqual(AppStrings.text(key,language:.english),e.en);XCTAssertEqual(AppStrings.text(key,language:.japanese),e.ja)}
        XCTAssertEqual(AppStrings.formatted(.menuAbout,language:.english,values:["app":"literal 中文 한국어 {app}"]),"About literal 中文 한국어 {app}")
    }
}
