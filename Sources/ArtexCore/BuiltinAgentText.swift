import Foundation

/// Presentation of exact pinned defaults only; never changes persisted agent data.
public enum BuiltinAgentText {
    private static let autoDescription = "平台操作助手：用工具管理任务(建/看/暂停/给提示)与资产，并可创建/修改 skill、自定义工具、MCP。"
    private static let pentestDescription = "独立渗透 agent：一人从侦察→找攻击面→深入利用→验证→收尾走完整条链，自己规划、自己执行、自己对抗式验证。"
    public static func description(key: String, original: String, language: AppLanguage) -> String {
        let expected: String
        let resource: AppStringKey
        switch key {
        case "auto": expected = autoDescription; resource = .chatAutoDescription
        case "pentest": expected = pentestDescription; resource = .chatPentestDescription
        default: return original
        }
        guard Data(original.utf8) == Data(expected.utf8) else { return original }
        return AppStrings.text(resource, language: language)
    }
    public static func name(key: String, original: String, language: AppLanguage) -> String {
        guard key == "pentest", Data(original.utf8) == Data("渗透测试".utf8) else { return original }
        return AppStrings.text(.chatPentestName, language: language)
    }
}
