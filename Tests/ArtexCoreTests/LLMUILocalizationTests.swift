import XCTest
@testable import ArtexCore

final class LLMUILocalizationTests: XCTestCase {
    private struct Fixture:Decodable {struct Entry:Decodable{let key:String;let en:String;let ja:String};let entries:[Entry]}
    func testAllLLMUIStringsMatchReviewedBilingualMatrix() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource:"llm-ui-localization",withExtension:"json",subdirectory:"Fixtures"))
        let fixture = try JSONDecoder().decode(Fixture.self,from:Data(contentsOf:url))
        XCTAssertEqual(fixture.entries.count,108)
        for entry in fixture.entries {
            let key = try XCTUnwrap(AppStringKey(rawValue:entry.key))
            XCTAssertEqual(AppStrings.text(key,language:.english),entry.en)
            XCTAssertEqual(AppStrings.text(key,language:.japanese),entry.ja)
        }
    }
    func testNamedFormattingNeverReinterpretsOpaqueModelText() {
        let model = "literal 中文 한국어 {latency} {model}"
        for (language,expected) in [
            (AppLanguage.english,"Connected · " + model + " · 12ms"),
            (.japanese,"接続成功 · " + model + " · 12ms")
        ] {
            XCTAssertEqual(AppStrings.formatted(.llmUITestSuccess,language:language,values:["model":model,"latency":"12"]),expected)
        }
        XCTAssertEqual(AppStrings.render(template:"{n} {n} {unknown} {broken",values:["n":"{unknown} 日本語"]),"{unknown} 日本語 {unknown} 日本語 {unknown} {broken")
        XCTAssertEqual(AppStrings.render(template:"plain 日本語",values:[:]),"plain 日本語")
        XCTAssertEqual(AppStrings.render(template:"A{empty}B",values:["empty":""]),"AB")
    }
    func testDisplayFormattingDoesNotChangeWireDraftOrRetryValues() throws {
        var draft = LLMProfileDraft();draft.name="literal {count} 中文 한국어";draft.model="fixture";draft.format = .openaiResponses
        let before = try draft.encoded();var policy = LLMRetryPolicy();policy.connect = .init(attempts:2,intervalMs:100)
        let retryBefore = try LLMWire.encode(policy)
        XCTAssertEqual(AppStrings.formatted(.llmUIModelCandidates,language:.english,values:["count":"3"]),"Model candidates (3)")
        XCTAssertEqual(AppStrings.formatted(.llmUIRates,language:.japanese,values:["second":"1.5","minute":"30"]),"1.5/秒 · 30/分")
        XCTAssertEqual(try draft.encoded(),before);XCTAssertEqual(try LLMWire.encode(policy),retryBefore)
        XCTAssertEqual(draft.format.rawValue,"openai-responses");XCTAssertEqual(draft.name,"literal {count} 中文 한국어")
    }
}
