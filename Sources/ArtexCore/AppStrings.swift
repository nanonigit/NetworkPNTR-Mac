import Foundation

public enum AppStringKey: String, CaseIterable, Sendable {
    case errorCredentials = "error.credentials"
    case errorForbidden = "error.forbidden"
    case errorRateLimited = "error.rateLimited"
    case errorDatabaseUnavailable = "error.databaseUnavailable"
    case errorHttpStatus = "error.httpStatus"
    case errorInvalidResponse = "error.invalidResponse"
    case errorKeychain = "error.keychain"
    case errorCommunication = "error.communication"
    case errorUploadInvalidFile = "error.uploadInvalidFile"
    case errorUploadInvalidFraming = "error.uploadInvalidFraming"
    case errorUploadTooLarge = "error.uploadTooLarge"
    case errorUploadChangedFile = "error.uploadChangedFile"
    case errorUploadReadFailure = "error.uploadReadFailure"

    case chatNew = "chat.New"
    case chatFilter = "chat.Filter"
    case chatAllAgents = "chat.AllAgents"
    case chatMultiSelect = "chat.MultiSelect"
    case chatDelete = "chat.Delete"
    case chatPinned = "chat.Pinned"
    case chatShow100 = "chat.Show100"
    case chatLoading = "chat.Loading"
    case chatNoConversations = "chat.NoConversations"
    case chatDeleteQuestion = "chat.DeleteQuestion"
    case chatDeleteConversation = "chat.DeleteConversation"
    case chatCancel = "chat.Cancel"
    case chatDeleteMessage = "chat.DeleteMessage"
    case chatAgent = "chat.Agent"
    case chatChoose = "chat.Choose"
    case chatModel = "chat.Model"
    case chatDefaultModel = "chat.DefaultModel"
    case chatSendKey = "chat.SendKey"
    case chatEnter = "chat.Enter"
    case chatCtrlEnter = "chat.CtrlEnter"
    case chatStopping = "chat.Stopping"
    case chatStop = "chat.Stop"
    case chatSending = "chat.Sending"
    case chatSend = "chat.Send"
    case chatFileReadFailure = "chat.FileReadFailure"
    case chatPickerFailure = "chat.PickerFailure"
    case chatSelectPrefix = "chat.SelectPrefix"
    case chatConversationName = "chat.ConversationName"
    case chatConversationPrefix = "chat.ConversationPrefix"
    case chatUnpin = "chat.Unpin"
    case chatRename = "chat.Rename"
    case chatActionsPrefix = "chat.ActionsPrefix"
    case chatRemoveAttachmentPrefix = "chat.RemoveAttachmentPrefix"
    case chatRemoveAttachmentHelp = "chat.RemoveAttachmentHelp"
    case chatCancelUpload = "chat.CancelUpload"
    case chatAttach = "chat.Attach"
    case chatAttachPrompt = "chat.AttachPrompt"
    case chatAttachMessage = "chat.AttachMessage"
    case chatPreparingFiles = "chat.PreparingFiles"
    case chatUploading = "chat.Uploading"
    case chatProcessingFiles = "chat.ProcessingFiles"
    case chatRetry = "chat.Retry"
    case chatLoadingHistory = "chat.LoadingHistory"
    case chatOlderMessages = "chat.OlderMessages"
    case chatNoMessages = "chat.NoMessages"
    case chatStartHint = "chat.StartHint"
    case chatLatest = "chat.Latest"
    case chatYou = "chat.You"
    case chatDetails = "chat.Details"
    case chatDetailsHelp = "chat.DetailsHelp"
    case chatEventDetails = "chat.EventDetails"
    case chatNoDetails = "chat.NoDetails"
    case chatLoadingDetails = "chat.LoadingDetails"
    case chatDetailsFailed = "chat.DetailsFailed"
    case chatMessage = "chat.Message"
    case chatLoadingBody = "chat.LoadingBody"
    case chatReloadBody = "chat.ReloadBody"
    case chatRemoveMentionPrefix = "chat.RemoveMentionPrefix"
    case chatCiteRecord = "chat.CiteRecord"
    case chatSearchingMentions = "chat.SearchingMentions"
    case chatSearchAgain = "chat.SearchAgain"
    case chatNoMatches = "chat.NoMatches"
    case chatLoadMore = "chat.LoadMore"
    case chatRetryMore = "chat.RetryMore"
    case chatMentionCandidates = "chat.MentionCandidates"
    case chatCompany = "chat.Company"
    case chatApp = "chat.App"
    case chatDomain = "chat.Domain"
    case chatSubdomain = "chat.Subdomain"
    case chatService = "chat.Service"
    case chatInputTokens = "chat.InputTokens"
    case chatOutputTokens = "chat.OutputTokens"
    case chatAutoDescription = "chat.AutoDescription"
    case chatPentestName = "chat.PentestName"
    case chatPentestDescription = "chat.PentestDescription"
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
