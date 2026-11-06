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

    public init(profileID: Int64?, maxTurns: String, runSeconds: String) {
        self.profileID = profileID
        self.maxTurns = maxTurns
        self.runSeconds = runSeconds
    }
}

struct AgentExecutionPatch: Encodable {
    let changesProfile: Bool
    let profileID: Int64?
    let maxTurns: Int32?
    let runSeconds: Int32?

    private enum CodingKeys: String, CodingKey {
        case profileID = "llm_profile_id"
        case maxTurns = "max_turns"
        case runSeconds = "run_seconds"
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
        guard changesProfile || maxTurns != nil || runSeconds != nil else { return nil }
    }

    func encode(to encoder: any Encoder) throws {
        var fields = encoder.container(keyedBy: CodingKeys.self)
        if changesProfile {
            if let profileID { try fields.encode(profileID, forKey: .profileID) }
            else { try fields.encodeNil(forKey: .profileID) }
        }
        try fields.encodeIfPresent(maxTurns, forKey: .maxTurns)
        try fields.encodeIfPresent(runSeconds, forKey: .runSeconds)
    }

    func matches(_ saved: AgentExecutionDraft) -> Bool {
        (!changesProfile || profileID == saved.profileID)
            && (maxTurns.map { $0 == Int32(saved.maxTurns) } ?? true)
            && (runSeconds.map { $0 == Int32(saved.runSeconds) } ?? true)
    }
}
