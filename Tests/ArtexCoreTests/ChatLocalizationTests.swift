import XCTest
@testable import ArtexCore

final class ChatLocalizationTests: XCTestCase {
    func testChatControlsResolveBothLocalesFromPackagedResources() {
        XCTAssertEqual(AppStrings.text(.chatNew, language: .english), "New conversation")
        XCTAssertEqual(AppStrings.text(.chatNew, language: .japanese), "新しい会話")
        XCTAssertEqual(AppStrings.text(.chatAttach, language: .english), "Attach files")
        XCTAssertEqual(AppStrings.text(.chatSend, language: .english), "Send")
        XCTAssertEqual(AppStrings.text(.chatNoMessages, language: .english), "No messages yet")
    }
    func testOnlyExactPinnedBuiltinDefaultsArePresentedInSelectedLanguage() {
        let auto = "平台操作助手：用工具管理任务(建/看/暂停/给提示)与资产，并可创建/修改 skill、自定义工具、MCP。"
        let pentest = "独立渗透 agent：一人从侦察→找攻击面→深入利用→验证→收尾走完整条链，自己规划、自己执行、自己对抗式验证。"
        for language in AppLanguage.allCases {
            XCTAssertEqual(BuiltinAgentText.description(key: "auto", original: auto, language: language), AppStrings.text(.chatAutoDescription, language: language))
            XCTAssertEqual(BuiltinAgentText.description(key: "pentest", original: pentest, language: language), AppStrings.text(.chatPentestDescription, language: language))
            XCTAssertEqual(BuiltinAgentText.name(key: "pentest", original: "渗透测试", language: language), AppStrings.text(.chatPentestName, language: language))
            XCTAssertEqual(BuiltinAgentText.description(key: "custom", original: auto, language: language), auto)
            XCTAssertEqual(BuiltinAgentText.description(key: "auto", original: auto + " custom", language: language), auto + " custom")
            XCTAssertEqual(BuiltinAgentText.name(key: "custom", original: "渗透测试", language: language), "渗透测试")
            XCTAssertEqual(BuiltinAgentText.name(key: "pentest", original: "User 中文 한국어", language: language), "User 中文 한국어")
            XCTAssertEqual(BuiltinAgentText.name(key: "auto", original: "Auto", language: language), "Auto")
            XCTAssertEqual(BuiltinAgentText.description(key: "pentest", original: "", language: language), "")
        }
    }
}
