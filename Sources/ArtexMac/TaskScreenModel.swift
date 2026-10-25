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
    let creation: TaskCreationModel?
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
    init(store: TaskStore, creationService: TaskCreationService? = nil, stagingUploader: (any TaskStagingUploading)? = nil) {
        self.store = store
        creation = creationService.map { TaskCreationModel(store: store, service: $0, uploader: stagingUploader) }
    }
    func beginCreate() -> Bool {
        guard !busy, dialog == nil, let creation else { return false }
        return creation.open() != nil
    }
    var busy: Bool { isSubmitting || store.isMutating || creation?.isSubmitting == true || creation?.isUploading == true || creation?.isPicking == true }
    func select(_ id: String?) {
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
    func stop() { lifecycle = UUID(); selectionTask?.cancel(); selectionTask = nil; store.stop() }
    func reset() {
        stop(); creation?.reset(); store.reset(); dialog = nil; renameDraft = ""; query = ""; status = nil
        sort = .id; ascending = false; deletionOptions = .init(); dialogUncertain = false; dialogFailure = nil
    }
}
