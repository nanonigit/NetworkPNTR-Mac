import ArtexCore
import Foundation
import Observation

struct TaskCreationContext: Identifiable { let id = UUID() }
struct TaskTemplateDecision: Identifiable {
    let id = UUID()
    let contextID: UUID
    let template: TaskTemplateOption
}
struct TaskChoiceState<Value> {
    var value: [Value]?
    var failure: AppErrorMessage?
}

@MainActor @Observable final class TaskCreationModel {
    private(set) var context: TaskCreationContext?
    private(set) var form = TaskCreationForm()
    private(set) var selectedTemplateID: Int64?
    private(set) var pendingTemplate: TaskTemplateDecision?
    private(set) var categories = TaskChoiceState<TaskNamedOption>()
    private(set) var companies = TaskChoiceState<TaskNamedOption>()
    private(set) var profiles = TaskChoiceState<TaskProfileOption>()
    private(set) var templates = TaskChoiceState<TaskTemplateOption>()
    private(set) var sources = TaskChoiceState<TaskRecord>()
    private(set) var isLoading = false
    private(set) var isSubmitting = false
    private(set) var uncertain = false
    private(set) var failure: AppErrorMessage?
    private(set) var draftID = UUID()
    private(set) var uploadCount = 0
    private(set) var uploadProgress: BackendUploadProgress?
    private(set) var uploadFailure: AppErrorMessage?
    private(set) var isPicking = false
    private(set) var uploadID: UUID?
    var isUploading: Bool { uploadID != nil }
    var uploadsAvailable: Bool { uploader != nil }
    @ObservationIgnored private let uploader: (any TaskStagingUploading)?
    @ObservationIgnored private var uploadWorker: Task<[TaskStagedAttachment],Error>?
    @ObservationIgnored private var uploadPump: Task<Void,Never>?
    @ObservationIgnored private var uploadContinuation: AsyncStream<BackendUploadProgress>.Continuation?
    let categoryWorkspace: TaskCategoryWorkspace?
    var categoryBusy: Bool { categoryWorkspace?.context != nil || categoryWorkspace?.isMutating == true }
    let templateManager: TaskTemplateManager?
    @ObservationIgnored private let store: TaskStore
    @ObservationIgnored private let service: TaskCreationService
    @ObservationIgnored private var loadTicket = UUID()
    @ObservationIgnored private var categoryCatalogTicket = UUID()
    init(store: TaskStore, service: TaskCreationService, uploader: (any TaskStagingUploading)? = nil, templateService: TaskTemplateService? = nil, categoryWorkspace: TaskCategoryWorkspace? = nil) {
        self.store = store; self.service = service; self.uploader = uploader; self.categoryWorkspace = categoryWorkspace
        templateManager = templateService.map { TaskTemplateManager(service: $0) }
        templateManager?.onReceipt = { [weak self] receipt in self?.receiveTemplate(receipt) }
    }
    func open() -> UUID? {
        guard context == nil, !isSubmitting, templateManager?.isMutating != true, !categoryBusy else { return nil }
        let next = TaskCreationContext(); context = next
        if !uncertain { failure = nil }
        return next.id
    }
    func close(contextID: UUID) {
        guard context?.id == contextID, !isSubmitting, !isPicking, templateManager?.context == nil, templateManager?.isMutating != true, !categoryBusy else { return }
        finishContext()
    }
    private func finishContext() {
        if isUploading { cancelUpload(); uploadFailure = AppErrorMessage(key: .taskUploadInterrupted) }
        context = nil; pendingTemplate = nil; loadTicket = UUID(); isLoading = false
    }
    func discard(contextID: UUID) {
        guard context?.id == contextID, !isSubmitting, !isPicking, templateManager?.context == nil, templateManager?.isMutating != true, !categoryBusy else { return }
        close(contextID: contextID); clearUploads(); form = .init(); selectedTemplateID = nil; uncertain = false; failure = nil
    }
    func reset() {
        categoryWorkspace?.reset()
        templateManager?.reset()
        clearUploads()
        context = nil; pendingTemplate = nil; loadTicket = UUID(); isLoading = false
        form = .init(); selectedTemplateID = nil; uncertain = false; failure = nil
        categories = .init(); companies = .init(); profiles = .init(); templates = .init(); sources = .init()
    }
    private func editable(_ id: UUID) -> Bool { context?.id == id && !isSubmitting && !uncertain && pendingTemplate == nil && templateManager?.context == nil && templateManager?.isMutating != true && !categoryBusy }
    func update<Value>(_ key: WritableKeyPath<TaskCreationForm, Value>, value: Value, contextID: UUID) {
        guard editable(contextID) else { return }; form[keyPath: key] = value
    }
    func toggle<Value: Equatable>(_ key: WritableKeyPath<TaskCreationForm, [Value]>, value: Value, maximum: Int, contextID: UUID) {
        guard editable(contextID) else { return }
        if let index = form[keyPath: key].firstIndex(of: value) { form[keyPath: key].remove(at: index) }
        else if form[keyPath: key].count < maximum { form[keyPath: key].append(value) }
    }
    func setSelected<Value: Equatable>(_ key: WritableKeyPath<TaskCreationForm, [Value]>, value: Value, selected: Bool, maximum: Int, contextID: UUID) {
        guard editable(contextID), form[keyPath: key].contains(value) != selected else { return }
        toggle(key, value: value, maximum: maximum, contextID: contextID)
    }
    func moveProfile(id: Int64, offset: Int, contextID: UUID) {
        guard editable(contextID), offset == 1 || offset == -1, let index = form.draft.llmProfileIds.firstIndex(of: id) else { return }
        let target = index + offset
        guard form.draft.llmProfileIds.indices.contains(target) else { return }
        form.draft.llmProfileIds.swapAt(index, target)
    }
    func chooseTemplate(_ id: Int64?, contextID: UUID) {
        guard editable(contextID), !isUploading else { return }
        if let id {
            guard let template = templates.value?.first(where: { $0.id == id }) else { return }
            let hasText = !ChatText.trim(form.draft.description).isEmpty || !ChatText.trim(form.draft.goal).isEmpty
            if hasText && (!form.draft.description.utf8.elementsEqual(template.description.utf8) || !form.draft.goal.utf8.elementsEqual(template.goal.utf8)) {
                pendingTemplate = .init(contextID: contextID, template: template); return
            }
            form.apply(template); uploadCount = 0; uploadFailure = nil
        }
        selectedTemplateID = id
    }
    func resolveTemplate(id: UUID, apply: Bool, contextID: UUID) {
        guard context?.id == contextID, !isSubmitting, !uncertain, !isUploading, let pending = pendingTemplate,
              pending.id == id, pending.contextID == contextID else { return }
        if apply { form.apply(pending.template); uploadCount = 0; uploadFailure = nil; selectedTemplateID = pending.template.id }
        pendingTemplate = nil
    }
    func addRule(contextID: UUID) { guard editable(contextID) else { return }; form.rules.append(.init()) }
    func removeRule(id: UUID, contextID: UUID) { guard editable(contextID) else { return }; form.rules.removeAll { $0.id == id } }
    func updateRule<Value>(id: UUID, key: WritableKeyPath<TaskInterceptRuleDraft, Value>, value: Value, contextID: UUID) {
        guard editable(contextID), let index = form.rules.firstIndex(where: { $0.id == id }) else { return }
        form.rules[index].rule[keyPath: key] = value
    }
    func load(contextID: UUID) async {
        guard context?.id == contextID, !isLoading, !isSubmitting, templateManager?.context == nil, templateManager?.isMutating != true, !categoryBusy, !Task.isCancelled else { return }
        let ticket = UUID(); loadTicket = ticket; isLoading = true
        defer { if loadTicket == ticket { isLoading = false } }
        async let a: Void = loadCategories(ticket)
        async let b: Void = loadCompanies(ticket)
        async let c: Void = loadProfiles(ticket)
        async let d: Void = loadTemplates(ticket)
        async let e: Void = loadSources(ticket)
        _ = await (a,b,c,d,e)
    }
    private func fetch<Value: Sendable>(ticket: UUID, operation: () async throws -> [Value],
                                        apply: ([Value]?, AppErrorMessage?) -> Void) async {
        do {
            let value = try await operation()
            guard loadTicket == ticket, !Task.isCancelled else { return }
            apply(value, nil)
        } catch {
            guard loadTicket == ticket, !Task.isCancelled else { return }
            apply(nil, AppErrorMessage(error))
        }
    }
    private func loadCategories(_ ticket: UUID) async {
        let categoryTicket = categoryCatalogTicket
        await fetch(ticket: ticket, operation: { try await self.service.categories() }) { value, error in
            guard self.categoryCatalogTicket == categoryTicket else { return }
            if let value { self.categories.value = value }; self.categories.failure = error
        }
    }
    private func loadCompanies(_ ticket: UUID) async {
        await fetch(ticket: ticket, operation: { try await self.service.companies() }) { value, error in
            if let value { self.companies.value = value }; self.companies.failure = error
        }
    }
    private func loadProfiles(_ ticket: UUID) async {
        await fetch(ticket: ticket, operation: { try await self.service.profiles() }) { value, error in
            if let value { self.profiles.value = value }; self.profiles.failure = error
        }
    }
    private func loadTemplates(_ ticket: UUID) async {
        await fetch(ticket: ticket, operation: { try await self.service.templates() }) { value, error in
            if let value { self.templates.value = value }; self.templates.failure = error
        }
    }
    private func loadSources(_ ticket: UUID) async {
        await fetch(ticket: ticket, operation: { try await self.service.sources() }) { value, error in
            if let value { self.sources.value = value }; self.sources.failure = error
        }
    }
    private func validateChoices(_ draft: TaskCreateDraft) throws {
        func contains<T: Hashable>(_ selected: [T], _ available: [T]?) -> Bool { selected.isEmpty || available.map { Set(selected).isSubset(of: Set($0)) } == true }
        guard contains(draft.llmProfileIds, profiles.value?.map(\.id)), contains(draft.companyIds, companies.value?.map(\.id)),
              contains(draft.sourceTaskIds, sources.value?.map(\.id)), contains(draft.categoryId.map { [$0] } ?? [], categories.value?.map(\.id)) else { throw TaskInputError.invalidCreation }
    }
    func submit(contextID: UUID) async -> Bool {
        guard editable(contextID), !isLoading, !isPicking, !isUploading, !Task.isCancelled else { return false }
        let payload: TaskCreateDraft
        do { payload = try form.payload(); try validateChoices(payload) }
        catch { failure = AppErrorMessage(error); return false }
        isSubmitting = true; failure = nil
        defer { isSubmitting = false }
        let outcome = await store.create(payload)
        guard context?.id == contextID else { return false }
        switch outcome {
        case .confirmed:
            clearUploads()
            form = .init(); selectedTemplateID = nil; context = nil; failure = nil; uncertain = false; return true
        case .unconfirmed: uncertain = true; failure = store.mutationFailure; return false
        case .rejected: failure = store.mutationFailure; return false
        case .notStarted, .discarded: return false
        }
    }
    func setPickerPresented(_ presented: Bool, contextID: UUID) {
        guard context?.id == contextID, !isSubmitting, !isUploading, !categoryBusy, templateManager?.context == nil, templateManager?.isMutating != true else { return }
        isPicking = presented
    }
    func pickerFailed(contextID: UUID) {
        guard context?.id == contextID else { return }
        uploadFailure = AppErrorMessage(key: .errorUploadUnavailable)
    }
    func suspendAttachments() {
        if context != nil, categoryWorkspace?.context?.inlineOwner == context?.id { categoryWorkspace?.suspend() }
        templateManager?.suspend(); isPicking = false
        if !isSubmitting { finishContext() }
    }
    func uploadFiles(_ files: [URL], language: AppLanguage, contextID: UUID) async -> Bool {
        guard context?.id == contextID, !isSubmitting, !uncertain, pendingTemplate == nil,
              !isPicking, !isUploading, templateManager?.context == nil, templateManager?.isMutating != true, !categoryBusy, !files.isEmpty, !Task.isCancelled else { return false }
        guard let uploader else { pickerFailed(contextID: contextID); return false }
        let id = UUID(), draft = draftID
        let (stream, continuation) = AsyncStream<BackendUploadProgress>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let worker = Task { @MainActor in
            try Task.checkCancellation()
            let result = try await uploader.uploadTaskStaging(draftID: draft, files: files, progress: { continuation.yield($0) })
            try Task.checkCancellation()
            guard result.count == files.count, result.allSatisfy({ $0.draftID == draft }) else { throw BackendAPIError.invalidResponse }
            return result
        }
        uploadID = id; uploadProgress = nil; uploadFailure = nil
        uploadWorker = worker; uploadContinuation = continuation
        uploadPump = Task { @MainActor [weak self] in
            for await value in stream {
                guard let self, self.uploadID == id, self.context?.id == contextID, !Task.isCancelled else { return }
                self.uploadProgress = value
            }
        }
        defer { finishUpload(id: id) }
        do {
            let attachments = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel(); continuation.finish() }
            guard uploadID == id, self.context?.id == contextID, draftID == draft, !Task.isCancelled else { return false }
            form.draft.description = TaskUploadManifest.appending(to: form.draft.description, attachments: attachments, language: language)
            uploadCount += attachments.count
            return true
        } catch {
            guard uploadID == id, self.context?.id == contextID, draftID == draft else { return false }
            uploadFailure = error is CancellationError ? AppErrorMessage(key: .taskUploadInterrupted) : AppErrorMessage(error)
            return false
        }
    }
    func cancelUpload() {
        uploadWorker?.cancel(); uploadPump?.cancel(); uploadContinuation?.finish()
        uploadWorker = nil; uploadPump = nil; uploadContinuation = nil; uploadID = nil; uploadProgress = nil
    }
    func clearUploads() {
        cancelUpload(); draftID = UUID(); uploadCount = 0; uploadFailure = nil; isPicking = false
    }
    private func finishUpload(id: UUID) {
        guard uploadID == id else { return }
        uploadPump?.cancel(); uploadContinuation?.finish()
        uploadWorker = nil; uploadPump = nil; uploadContinuation = nil; uploadID = nil; uploadProgress = nil
    }
    func openTemplateManager(asSeed: Bool, contextID: UUID) -> Bool {
        guard editable(contextID), !isLoading, !isPicking, !isUploading, let manager = templateManager else { return false }
        var seed: TaskTemplateDraft?
        if asSeed {
            guard !ChatText.trim(form.draft.description).isEmpty, !ChatText.trim(form.draft.goal).isEmpty else { return false }
            var value = TaskTemplateDraft(); value.description = form.draft.description; value.goal = form.draft.goal
            value.categoryId = form.draft.categoryId; value.interceptRules = form.rules.map(\.rule); seed = value
        }
        return manager.open(seed: seed, templates: templates.value ?? []) != nil
    }
    func openCategoryCreator(contextID: UUID) -> Bool {
        guard editable(contextID), !isLoading, !isPicking, !isUploading, let categoryWorkspace else { return false }
        return categoryWorkspace.open(tasks:store.list.value ?? [],inlineOwner:contextID) != nil
    }
    func receiveCategories(_ rows: [TaskCategoryRecord]) {
        categoryCatalogTicket = UUID()
        categories.value = rows.map { .init(id:$0.id,name:$0.name) }; categories.failure = nil
        templateManager?.receiveCategories(rows)
    }
    func receiveCategory(_ change: TaskCategoryChange, inlineOwner: UUID?) {
        guard let inlineOwner, context?.id == inlineOwner, case .saved(let row) = change else { return }
        form.draft.categoryId = row.id
    }
    private func receiveTemplate(_ receipt: TaskTemplateReceipt) {
        switch receipt {
        case .saved(let value): templates.value = [value] + (templates.value ?? []).filter { $0.id != value.id }; templates.failure = nil
        case .deleted(let id): templates.value?.removeAll { $0.id == id }; if selectedTemplateID == id { selectedTemplateID = nil }
        }
    }

}
