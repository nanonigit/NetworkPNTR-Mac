import ArtexCore
import Foundation
import Observation

struct TaskDialog: Identifiable {
    enum Kind { case rename, delete }
    let id = UUID()
    let kind: Kind
    let task: TaskRecord
}

/// Window-owned inputs and captured dialog owners survive language changes and sidebar navigation.
@MainActor @Observable final class TaskScreenModel {
    let store: TaskStore
    let archives: TaskArchiveStore?
    let archiveActions: TaskArchiveWorkspace?
    let creation: TaskCreationModel?
    let bulk: TaskBulkWorkspace?
    let categories: TaskCategoryWorkspace?
    var categoryFilter: TaskCategoryFilter = .all
    var query = ""
    var status: String?
    var sort: TaskSortField = .id
    var ascending = false
    var renameDraft = ""
    var deletionOptions = TaskDeletionOptions()
    private(set) var dialog: TaskDialog?
    private(set) var dialogUncertain = false
    private(set) var dialogFailure: AppErrorMessage?
    private(set) var isSubmitting = false
    @ObservationIgnored private var selectionTask: Task<Void, Never>?
    @ObservationIgnored private var lifecycle = UUID()
    init(store: TaskStore, creationService: TaskCreationService? = nil, stagingUploader: (any TaskStagingUploading)? = nil, templateService: TaskTemplateService? = nil, categoryService: TaskCategoryService? = nil, bulkService: TaskService? = nil, archiveService: TaskArchiveService? = nil) {
        self.store = store
        let archiveStore = archiveService.map { TaskArchiveStore(service:$0) }
        archives = archiveStore
        if let archiveStore, let archiveService { archiveActions = TaskArchiveWorkspace(store:store,archives:archiveStore,service:archiveService) }
        else { archiveActions = nil }
        let workspace = categoryService.map { TaskCategoryWorkspace(service:$0,store:store) }
        categories = workspace
        bulk = bulkService.map { TaskBulkWorkspace(store:store,service:$0,categoryService:categoryService,catalog:workspace) }
        creation = creationService.map { TaskCreationModel(store: store, service: $0, uploader: stagingUploader, templateService: templateService, categoryWorkspace:workspace) }
        archiveActions?.onReceipt = { [weak self] captured in
            guard let self else { return }
            self.categories?.markStale()
            if captured.kind == .archive, captured.batch, let selectedBulk = self.bulk { selectedBulk.clearSelection(owner:selectedBulk.viewOwner) }
        }
        categories?.onCatalog = { [weak self] rows in self?.receivedCatalog(rows) }
        categories?.onChange = { [weak self] change,owner in self?.creation?.receiveCategory(change,inlineOwner:owner) }
    }
    func beginArchive(_ task: TaskRecord) -> Bool {
        guard !busy, dialog == nil, creation?.context == nil else { return false }
        return archiveActions?.beginArchive([task],batch:false) ?? false
    }
    func beginSelectedArchive() -> Bool {
        guard !busy, dialog == nil, creation?.context == nil, let bulk else { return false }
        let rows = (store.list.value ?? []).filter { bulk.selectedIDs.contains($0.id) }
        return archiveActions?.beginArchive(rows,batch:true) ?? false
    }
    func beginArchivedAction(_ kind: TaskArchiveActionKind, records: [TaskArchiveRecord]) -> Bool {
        guard !busy, dialog == nil, creation?.context == nil else { return false }
        return archiveActions?.begin(kind,archives:records) ?? false
    }
    func beginBulk(_ kind: TaskBulkKind) -> Bool {
        guard !busy, dialog == nil, creation?.context == nil, let bulk else { return false }; return bulk.begin(kind)
    }
    func setBulkSelected(_ id: String, selected: Bool, owner: UUID) {
        guard !busy, dialog == nil, creation?.context == nil else { return }; bulk?.setSelected(id,selected:selected,owner:owner)
    }
    func setBulkVisible(_ ids: [String], selected: Bool, owner: UUID) {
        guard !busy, dialog == nil, creation?.context == nil else { return }; bulk?.setAll(ids:ids,selected:selected,owner:owner)
    }
    func beginCategories() -> Bool {
        guard !busy, dialog == nil, creation?.context == nil, let categories else { return false }
        return categories.open(tasks:store.list.value ?? []) != nil
    }
    private func receivedCatalog(_ rows: [TaskCategoryRecord]) {
        creation?.receiveCategories(rows)
        if case .category(let id) = categoryFilter, !rows.contains(where:{$0.id == id}) { categoryFilter = .all }
    }
    func beginCreate() -> Bool {
        guard !busy, dialog == nil, let creation else { return false }
        return creation.open() != nil
    }
    var busy: Bool { archiveActions?.context != nil || archiveActions?.acknowledgement != nil || archiveActions?.isSubmitting == true || archives?.isMutating == true || bulk?.context != nil || bulk?.isMutating == true || bulk?.acknowledgement != nil || categories?.context != nil || categories?.isMutating == true || isSubmitting || store.isMutating || creation?.isSubmitting == true || creation?.isUploading == true || creation?.isPicking == true || creation?.templateManager?.context != nil || creation?.templateManager?.isMutating == true }
    func select(_ id: String?) {
        guard archiveActions?.context == nil, archiveActions?.isSubmitting != true, bulk?.context == nil, bulk?.isMutating != true else { return }
        selectionTask?.cancel()
        selectionTask = Task { await store.select(id: id) }
    }
    func beginRename(_ task: TaskRecord) -> Bool {
        guard !busy, creation?.context == nil else { return false }
        dialog = .init(kind: .rename, task: task); renameDraft = task.name; dialogUncertain = false; dialogFailure = nil
        return true
    }
    func beginDelete(_ task: TaskRecord) -> Bool {
        guard !busy, creation?.context == nil else { return false }
        dialog = .init(kind: .delete, task: task); deletionOptions = .init(); dialogUncertain = false; dialogFailure = nil
        return true
    }
    func closeDialog(id: UUID) { guard !busy, dialog?.id == id else { return }; dialog = nil; renameDraft = ""; dialogUncertain = false; dialogFailure = nil }
    func submit(dialogID: UUID) async -> Bool {
        guard !busy, !dialogUncertain, let context = dialog, context.id == dialogID else { return false }
        let name = renameDraft; let options = deletionOptions
        isSubmitting = true; defer { isSubmitting = false }
        switch context.kind {
        case .rename: return finish(await store.update(id: context.task.id, patch: .init(name: name)), context: context.id)
        case .delete: return finish(await store.delete(id: context.task.id, options: options), context: context.id)
        }
    }
    private func finish<Value>(_ result: TaskMutationOutcome<Value>, context: UUID) -> Bool {
        guard dialog?.id == context else { return false }
        switch result {
        case .confirmed: dialog = nil; renameDraft = ""; return true
        case .unconfirmed: dialogFailure = store.mutationFailure; dialogUncertain = true; return false
        case .rejected: dialogFailure = store.mutationFailure; return false
        case .notStarted, .discarded: return false
        }
    }
    func togglePin(_ task: TaskRecord) async {
        guard !busy else { return }; isSubmitting = true; defer { isSubmitting = false }
        _ = await store.update(id: task.id, patch: .init(pinned: !task.pinned))
    }
    func control(_ task: TaskRecord) async {
        guard !busy, let action = TaskPresentation.controlAction(task.status) else { return }
        isSubmitting = true; defer { isSubmitting = false }
        _ = await store.control(id: task.id, action: action)
    }
    func refresh() async {
        guard !busy else { return }
        let ticket = lifecycle; await store.refreshList()
        if ticket == lifecycle, !Task.isCancelled { await store.refreshSelected() }
    }
    func stop() { archiveActions?.suspend(); archives?.stop(); bulk?.suspend(); categories?.suspend(); lifecycle = UUID(); selectionTask?.cancel(); selectionTask = nil; creation?.suspendAttachments(); store.stop() }
    func reset() {
        stop(); archiveActions?.reset(); archives?.reset(); bulk?.reset(); categories?.reset(); categoryFilter = .all; creation?.reset(); store.reset(); dialog = nil; renameDraft = ""; query = ""; status = nil
        sort = .id; ascending = false; deletionOptions = .init(); dialogUncertain = false; dialogFailure = nil
    }
}
