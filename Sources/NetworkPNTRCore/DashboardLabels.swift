public enum DashboardLabelDomain: String, CaseIterable, Sendable {
    case task, engine, severity, activity
}

/// Display-only labels for pinned identifiers; unknown and custom values remain literal.
public enum DashboardLabels {
    public static func text(_ raw: String, domain: DashboardLabelDomain, language: AppLanguage) -> String {
        let key: AppStringKey?
        if domain == .activity {
            switch raw {
            case "tool_use": key = .dashboardUIActivityToolUse
            case "tool_result": key = .dashboardUIActivityToolResult
            case "text": key = .dashboardUIActivityText
            case "thinking": key = .dashboardUIActivityThinking
            case "result": key = .dashboardUIActivityResult
            default: key = nil
            }
        } else { key = AppStringKey(rawValue: "dashboard.status." + domain.rawValue + "." + raw) }
        return key.map { AppStrings.text($0, language: language) } ?? raw
    }
    public static func activity(kind: String, tool: String?, language: AppLanguage) -> String {
        if kind == "tool_use", let tool { return tool }
        return text(kind, domain: .activity, language: language)
    }
}
