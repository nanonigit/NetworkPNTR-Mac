import Foundation

public enum AppStringKey: String, CaseIterable, Sendable {
    case productName = "shell.productName"
    case runtime = "shell.runtime"
    case account = "shell.account"
    case parity = "shell.parity"
    case features = "shell.features"
    case system = "shell.system"
    case language = "shell.language"
    case languageHelp = "shell.languageHelp"
    case guestReady = "shell.guestReady"
    case guestPrefix = "shell.guestPrefix"
    case catalogUnavailable = "shell.catalogUnavailable"
    case startRequired = "shell.startRequired"
    case authPreparation = "shell.authPreparation"
    case loginRequired = "shell.loginRequired"
    case dashboardLogin = "shell.dashboardLogin"
    case chatLogin = "shell.chatLogin"
    case llmLogin = "shell.llmLogin"
    case plannedFeature = "shell.plannedFeature"
    case taskPending = "shell.taskPending"
    case selectedTask = "shell.selectedTask"
    case taskComparison = "shell.taskComparison"
    case close = "shell.close"
    case dashboard = "feature.dashboard"
    case chat = "feature.chat"
    case tasks = "feature.tasks"
    case findings = "feature.findings"
    case traffic = "feature.traffic"
    case commands = "feature.commands"
    case llmRecords = "feature.llmRecords"
    case assets = "feature.assets"
    case sync = "feature.sync"
    case workspace = "feature.workspace"
    case llm = "feature.llm"
    case agents = "feature.agents"
    case mcp = "feature.mcp"
    case skills = "feature.skills"
    case tools = "feature.tools"
    case notify = "feature.notify"
    case intercept = "feature.intercept"
    case assetIntercept = "feature.assetIntercept"
    case approvals = "feature.approvals"
    case logs = "feature.logs"
    case settings = "feature.settings"
}

public enum AppStrings {
    public static func text(_ key: AppStringKey, language: AppLanguage) -> String {
        lookup(key.rawValue, language: language)
    }
    static func lookup(_ key: String, language: AppLanguage) -> String {
        func localized(_ code: String) -> String? {
            guard let path = Bundle.module.path(forResource: code, ofType: "lproj"), let bundle = Bundle(path: path) else { return nil }
            let value = bundle.localizedString(forKey: key, value: nil, table: "Localizable")
            return value == key ? nil : value
        }
        return localized(language.rawValue) ?? localized("en") ?? key
    }
    public static func featureKey(_ id: String) -> AppStringKey? {
        switch id {
        case "dashboard": .dashboard
        case "chat": .chat
        case "tasks": .tasks
        case "findings": .findings
        case "traffic": .traffic
        case "commands": .commands
        case "llm-records": .llmRecords
        case "assets": .assets
        case "sync": .sync
        case "workspace": .workspace
        case "llm": .llm
        case "agents": .agents
        case "mcp": .mcp
        case "skills": .skills
        case "tools": .tools
        case "notify": .notify
        case "intercept": .intercept
        case "asset-intercept": .assetIntercept
        case "approvals": .approvals
        case "logs": .logs
        case "settings": .settings
        default: nil
        }
    }
    public static func featureTitle(_ id: String, fallback: String, language: AppLanguage) -> String {
        featureKey(id).map { text($0, language: language) } ?? fallback
    }
    public static func plannedFeature(phase: Int, path: String, language: AppLanguage) -> String {
        String(format: text(.plannedFeature, language: language), locale: language.locale, Int64(phase), path)
    }
}
