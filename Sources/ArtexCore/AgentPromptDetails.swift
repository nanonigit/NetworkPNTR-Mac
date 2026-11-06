import Foundation

public struct AgentPromptDetails: Decodable, Sendable {
    public struct Variable: Decodable, Sendable {
        public let name: String
        public let description: String
        public let example: String
        public let source: String

        public func displayDescription(agent: AgentCatalogEntry, language: AppLanguage) -> String {
            let resource: String
            if source == "runtime", name == "Now" || name == "DataDir" {
                // The server always replaces stored variables with these two runtime definitions.
                resource = "agent.variable.global.\(name)"
            } else if agent.builtin || agent.key == "retester" {
                resource = "agent.variable.\(agent.key).\(name)"
            } else {
                return description
            }
            let value = AppStrings.lookup(resource, language: language)
            return value == resource ? description : value
        }
    }

    public struct Version: Decodable, Identifiable, Sendable {
        public let version: Int
        public let templateText: String
        public let note: String?
        public let ts: String?
        public var id: Int { version }
    }

    public struct WrapUp: Sendable {
        public let prompt: String
        public let builtIn: String
        public let savedRounds: Int
        public let defaultRounds: Int

        public var usesDefault: Bool { prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        public var effectivePrompt: String { usesDefault ? builtIn : prompt }
        public var effectiveRounds: Int { savedRounds == 0 ? defaultRounds : savedRounds }
    }

    public let key: String
    public let prompt: String
    public let variables: [Variable]
    public let versions: [Version]
    public let wrapUp: WrapUp
    public let taskTimeout: WrapUp?
    public let execution: AgentExecutionDraft
    public let modelOptions: [AgentModelOption]
    public var showsExecutionLimits: Bool { key != "goals" && key != "mainagent" }

    private struct Identity: Decodable {
        let key: String
        let llmProfileId: Int64?
        let maxTurns: Int?
        let runSeconds: Int?
    }
    private enum CodingKeys: String, CodingKey {
        case agent, prompt, variables, versions, llmProfiles
        case wrapupPrompt, wrapupDefault, wrapupMaxTurns, wrapupMaxTurnsDefault
        case taskTimeoutWrapupSupported, taskTimeoutWrapupPrompt, taskTimeoutWrapupDefault
        case taskTimeoutWrapupMaxTurns, taskTimeoutWrapupMaxTurnsDefault
    }

    public init(from decoder: any Decoder) throws {
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        let agent = try fields.decode(Identity.self, forKey: .agent)
        key = agent.key
        execution = AgentExecutionDraft(profileID: agent.llmProfileId, maxTurns: String(agent.maxTurns ?? 0),
                                        runSeconds: String(agent.runSeconds ?? 600))
        modelOptions = try fields.decodeIfPresent([AgentModelOption].self, forKey: .llmProfiles) ?? []
        prompt = try fields.decodeIfPresent(String.self, forKey: .prompt) ?? ""
        variables = try fields.decodeIfPresent([Variable].self, forKey: .variables) ?? []
        versions = try fields.decodeIfPresent([Version].self, forKey: .versions) ?? []
        wrapUp = try WrapUp(
            prompt: fields.decodeIfPresent(String.self, forKey: .wrapupPrompt) ?? "",
            builtIn: fields.decodeIfPresent(String.self, forKey: .wrapupDefault) ?? "",
            savedRounds: fields.decodeIfPresent(Int.self, forKey: .wrapupMaxTurns) ?? 0,
            defaultRounds: fields.decodeIfPresent(Int.self, forKey: .wrapupMaxTurnsDefault) ?? 5
        )
        if try fields.decodeIfPresent(Bool.self, forKey: .taskTimeoutWrapupSupported) == true {
            taskTimeout = try WrapUp(
                prompt: fields.decodeIfPresent(String.self, forKey: .taskTimeoutWrapupPrompt) ?? "",
                builtIn: fields.decodeIfPresent(String.self, forKey: .taskTimeoutWrapupDefault) ?? "",
                savedRounds: fields.decodeIfPresent(Int.self, forKey: .taskTimeoutWrapupMaxTurns) ?? 0,
                defaultRounds: fields.decodeIfPresent(Int.self, forKey: .taskTimeoutWrapupMaxTurnsDefault) ?? 5
            )
        } else {
            taskTimeout = nil
        }
    }
}

public enum AgentWrapUpSection: String, Sendable, Hashable {
    case normal, taskTimeout

    var routeSuffix: String {
        switch self {
        case .normal: "/wrapup"
        case .taskTimeout: "/wrapup/task-timeout"
        }
    }
}

public struct AgentWrapUpDraft: Sendable {
    public var prompt: String
    public var rounds: String

    public init(prompt: String, rounds: String) {
        self.prompt = prompt
        self.rounds = rounds
    }

    public var validRounds: Int? {
        guard let value = Int32(rounds), value >= 0 else { return nil }
        return Int(value)
    }

    func matches(_ saved: AgentPromptDetails.WrapUp) -> Bool {
        validRounds == saved.savedRounds && prompt.utf8.elementsEqual(saved.prompt.utf8)
    }
}

extension AgentPromptDetails {
    func wrapUp(_ section: AgentWrapUpSection) -> WrapUp? {
        switch section {
        case .normal: wrapUp
        case .taskTimeout: taskTimeout
        }
    }
}
