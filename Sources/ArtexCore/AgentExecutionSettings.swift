public struct AgentModelOption: Decodable, Identifiable, Sendable {
    public let id: Int64
    public let name: String
    public let model: String
    public let isDefault: Bool
}

public struct AgentExecutionDraft: Sendable {
    public var profileID: Int64?
    public var maxTurns: String
    public var runSeconds: String
    public var webSearch: Bool
    public var interactiveShell: Bool

    public init(profileID: Int64?, maxTurns: String, runSeconds: String,
                webSearch: Bool = false, interactiveShell: Bool = false) {
        self.profileID = profileID
        self.maxTurns = maxTurns
        self.runSeconds = runSeconds
        self.webSearch = webSearch
        self.interactiveShell = interactiveShell
    }
}

struct AgentExecutionPatch: Encodable {
    let changesProfile: Bool
    let profileID: Int64?
    let maxTurns: Int32?
    let runSeconds: Int32?
    let webSearch: Bool?
    let interactiveShell: Bool?

    private enum CodingKeys: String, CodingKey {
        case profileID = "llm_profile_id"
        case maxTurns = "max_turns"
        case runSeconds = "run_seconds"
        case webSearch = "web_search"
        case interactiveShell = "interactive_shell"
    }

    init?(draft: AgentExecutionDraft, saved: AgentPromptDetails) {
        changesProfile = draft.profileID != saved.execution.profileID
        profileID = draft.profileID
        if changesProfile, let profileID,
           !saved.modelOptions.contains(where: { $0.id == profileID && $0.id > 0 }) { return nil }
        if saved.showsExecutionLimits {
            guard let turns = Int32(draft.maxTurns), turns >= 0,
                  let seconds = Int32(draft.runSeconds), seconds >= 0 else { return nil }
            maxTurns = turns == Int32(saved.execution.maxTurns) ? nil : turns
            runSeconds = seconds == Int32(saved.execution.runSeconds) ? nil : seconds
        } else {
            maxTurns = nil
            runSeconds = nil
        }
        webSearch = saved.showsExecutionTools && draft.webSearch != saved.execution.webSearch ? draft.webSearch : nil
        interactiveShell = saved.showsExecutionTools && draft.interactiveShell != saved.execution.interactiveShell
            ? draft.interactiveShell : nil
        guard changesProfile || maxTurns != nil || runSeconds != nil || webSearch != nil || interactiveShell != nil else {
            return nil
        }
    }

    func encode(to encoder: any Encoder) throws {
        var fields = encoder.container(keyedBy: CodingKeys.self)
        if changesProfile {
            if let profileID { try fields.encode(profileID, forKey: .profileID) }
            else { try fields.encodeNil(forKey: .profileID) }
        }
        try fields.encodeIfPresent(maxTurns, forKey: .maxTurns)
        try fields.encodeIfPresent(runSeconds, forKey: .runSeconds)
        try fields.encodeIfPresent(webSearch, forKey: .webSearch)
        try fields.encodeIfPresent(interactiveShell, forKey: .interactiveShell)
    }

    func matches(_ saved: AgentExecutionDraft) -> Bool {
        (!changesProfile || profileID == saved.profileID)
            && (maxTurns.map { $0 == Int32(saved.maxTurns) } ?? true)
            && (runSeconds.map { $0 == Int32(saved.runSeconds) } ?? true)
            && (webSearch.map { $0 == saved.webSearch } ?? true)
            && (interactiveShell.map { $0 == saved.interactiveShell } ?? true)
    }
}
