import Observation

@MainActor @Observable public final class AgentPromptEditor {
    private enum Phase { case ready, reading, saving, reloadRequired }
    private enum Mutation { case save, restore }
    private struct PendingVersion {
        let id: Int
        let expectedTemplate: String?

        func matches(_ version: AgentPromptDetails.Version) -> Bool {
            guard version.id == id else { return false }
            guard let expectedTemplate else { return true }
            return version.templateText.utf8.elementsEqual(expectedTemplate.utf8)
        }
    }

    private let key: String
    private let service: AgentCatalogService
    private var phase = Phase.ready
    private var pendingVersion: PendingVersion?

    public private(set) var details: AgentPromptDetails?
    public private(set) var draft = ""
    public private(set) var failure: AppErrorMessage?
    public private(set) var savedVersion: Int?
    public private(set) var restoredDefault = false

    public init(key: String, service: AgentCatalogService) {
        self.key = key
        self.service = service
    }

    public var isBusy: Bool { phase == .reading || phase == .saving }
    public var requiresRefresh: Bool { phase == .reloadRequired }
    public var canEdit: Bool { phase == .ready && details != nil }
    public var hasUnsavedChanges: Bool {
        guard let details else { return false }
        return !details.prompt.utf8.elementsEqual(draft.utf8)
    }
    public var canSave: Bool { canEdit && hasUnsavedChanges }

    public func edit(_ value: String) {
        guard canEdit else { return }
        draft = value
        savedVersion = nil
        restoredDefault = false
    }

    public func refresh() async {
        guard !isBusy else { return }
        let recovery = requiresRefresh
        let preserveDraft = hasUnsavedChanges
        phase = .reading
        failure = nil
        do {
            let latest = try await service.promptDetails(key: key)
            if let pendingVersion {
                guard latest.versions.contains(where: pendingVersion.matches) else {
                    throw BackendAPIError.invalidResponse
                }
                self.pendingVersion = nil
                draft = latest.prompt
            } else if !preserveDraft {
                draft = latest.prompt
            }
            details = latest
            phase = .ready
        } catch {
            failure = AppErrorMessage(error)
            phase = recovery ? .reloadRequired : .ready
        }
    }

    public func preview(template: String) async throws -> AgentPromptPreview {
        try await service.previewPrompt(key: key, template: template)
    }

    public func save() async {
        guard canSave else { return }
        await commit(.save)
    }

    public func restoreDefault() async {
        guard canEdit else { return }
        await commit(.restore)
    }

    private func commit(_ mutation: Mutation) async {
        guard !Task.isCancelled else { return }
        phase = .saving
        failure = nil
        savedVersion = nil
        restoredDefault = false
        do {
            let version: Int
            switch mutation {
            case .save:
                version = try await service.savePrompt(key: key, template: draft)
                pendingVersion = PendingVersion(id: version, expectedTemplate: draft)
            case .restore:
                version = try await service.restorePromptDefault(key: key)
                pendingVersion = PendingVersion(id: version, expectedTemplate: nil)
            }
            savedVersion = version
            restoredDefault = mutation == .restore
            phase = .reloadRequired
            await refresh()
        } catch BackendAPIError.status(400) {
            let message: AppStringKey = mutation == .restore ? .agentDetailsNoDefault : .agentDetailsInvalidTemplate
            failure = AppErrorMessage(key: message)
            phase = .ready
        } catch BackendAPIError.status(let status) where [401, 403, 404, 413].contains(status) {
            failure = AppErrorMessage(BackendAPIError.status(status))
            phase = .ready
        } catch {
            failure = AppErrorMessage(error)
            phase = .reloadRequired
        }
    }
}
