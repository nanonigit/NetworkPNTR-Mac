import Observation

@MainActor @Observable public final class AgentPromptEditor {
    private enum Phase { case ready, reading, saving, reloadRequired }

    private let key: String
    private let service: AgentCatalogService
    private var phase = Phase.ready
    private var pendingVersion: Int?

    public private(set) var details: AgentPromptDetails?
    public private(set) var draft = ""
    public private(set) var failure: AppErrorMessage?
    public private(set) var savedVersion: Int?

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
                guard latest.versions.contains(where: {
                    $0.version == pendingVersion && $0.templateText.utf8.elementsEqual(draft.utf8)
                }) else { throw BackendAPIError.invalidResponse }
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
        guard canSave, !Task.isCancelled else { return }
        phase = .saving
        failure = nil
        savedVersion = nil
        do {
            let version = try await service.savePrompt(key: key, template: draft)
            savedVersion = version
            pendingVersion = version
            phase = .reloadRequired
            await refresh()
        } catch BackendAPIError.status(400) {
            failure = AppErrorMessage(key: .agentDetailsInvalidTemplate)
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
