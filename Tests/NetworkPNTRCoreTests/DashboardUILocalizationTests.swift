import XCTest
@testable import NetworkPNTRCore

final class DashboardUILocalizationTests: XCTestCase {
    private func fixture(_ name:String) throws -> Data {
        try Data(contentsOf:XCTUnwrap(Bundle.module.url(forResource:name,withExtension:"json",subdirectory:"Fixtures")))
    }
    func testCompleteDashboardCatalogAndPlaceholderParity() throws {
        struct Matrix:Decodable {struct Entry:Decodable {let key:String;let en:String;let ja:String};let entries:[Entry]}
        let matrix = try JSONDecoder().decode(Matrix.self,from:fixture("dashboard-ui-localization"))
        XCTAssertEqual(matrix.entries.count,103)
        func tokens(_ text:String) -> Set<String> {
            Set(text.components(separatedBy:"{").dropFirst().compactMap{$0.split(separator:"}",maxSplits:1).first.map(String.init)})
        }
        for entry in matrix.entries {
            let key = try XCTUnwrap(AppStringKey(rawValue:entry.key))
            XCTAssertEqual(AppStrings.text(key,language:.english),entry.en)
            XCTAssertEqual(AppStrings.text(key,language:.japanese),entry.ja)
            XCTAssertEqual(tokens(entry.en),tokens(entry.ja))
        }
    }
    func testKnownStatusesMatchPinnedBrowserAndUnknownTextIsPreserved() throws {
        struct Fixture:Decodable {let baseline:String;let documents:[String:[String:[String:String]]]}
        let f = try JSONDecoder().decode(Fixture.self,from:fixture("dashboard-status-localization"))
        XCTAssertEqual(f.baseline,"e75ae371ad777ffd1eecdd28d2781a6519b05591")
        for language in AppLanguage.allCases {
            for domain in [DashboardLabelDomain.task,.engine,.severity] {
                for (raw,expected) in try XCTUnwrap(f.documents[language.rawValue]?[domain.rawValue]) {
                    XCTAssertEqual(DashboardLabels.text(raw,domain:domain,language:language),expected)
                }
            }
            for domain in DashboardLabelDomain.allCases {
                for raw in ["unknown", "Running", " running ", "中文 한국어", "{input}"] {
                    XCTAssertEqual(DashboardLabels.text(raw,domain:domain,language:language),raw)
                }
            }
        }
        for (kind,en,ja) in [("tool_use","Tool call","ツール実行"),("tool_result","Tool result","ツール結果"),("text","Text","本文"),("thinking","Thinking","思考"),("result","Result","結果")] {
            XCTAssertEqual(DashboardLabels.text(kind,domain:.activity,language:.english),en)
            XCTAssertEqual(DashboardLabels.text(kind,domain:.activity,language:.japanese),ja)
        }
        XCTAssertEqual(DashboardLabels.activity(kind:"tool_use",tool:"custom 中文 한국어 {input}",language:.english),"custom 中文 한국어 {input}")
        XCTAssertEqual(DashboardLabels.activity(kind:"tool_use",tool:nil,language:.japanese),"ツール実行")
        XCTAssertEqual(DashboardLabels.activity(kind:"text",tool:"unused",language:.japanese),"本文")
    }
    func testLocalizedSummariesDoNotAlterMetricsOrOpaqueDescriptions() throws {
        let snapshot = try LLMWire.decode(DashboardSnapshot.self,from:fixture("dashboard-snapshot"))
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from:"2026-10-22T12:00:00Z"))
        var calendar = Calendar(identifier:.gregorian);calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT:0))
        for source in DashboardTokenSource.allCases {
            let before = try DashboardMetrics(snapshot:snapshot,source:source,selection:.all,days:7,now:now,calendar:calendar)
            for language in AppLanguage.allCases {
                XCTAssertFalse(AppStrings.formatted(.dashboardUIDays,language:language,values:["days":"7"]).isEmpty)
                _ = DashboardLabels.text("running",domain:.task,language:language)
            }
            let after = try DashboardMetrics(snapshot:snapshot,source:source,selection:.all,days:7,now:now,calendar:calendar)
            XCTAssertEqual(before.tokens,after.tokens);XCTAssertEqual(before.daily.map(\.date),after.daily.map(\.date))
            XCTAssertEqual(before.daily.map(\.input),after.daily.map(\.input));XCTAssertEqual(before.assetTotal,after.assetTotal)
            XCTAssertEqual(before.severityCounts,after.severityCounts);XCTAssertEqual(before.runningTasks,after.runningTasks)
        }
        XCTAssertEqual(AppStrings.formatted(.dashboardUITaskDetail,language:.english,values:["description":"literal 中文 한국어 {description}"]),"Task details: literal 中文 한국어 {description}")
    }
}
