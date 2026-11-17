import NetworkPNTRCore
import Foundation
import Observation

struct FindingTrafficActionDialog: Identifiable {
    enum Kind { case edit(String), remove(String), reorder([String]), acknowledge }
    let id = UUID()
    let workspace, owner, unknownRevision: UUID
    let version: Int64
    let membership: [String]
    let kind: Kind
}

/// Confirmations own their exact version and membership; an uncertain command is never replayed.
@MainActor @Observable final class FindingTrafficActions {
    private(set) var dialog: FindingTrafficActionDialog?
    var roleDraft: FindingTrafficRole?
    var noteDraft = ""
    private(set) var isSubmitting = false
    private(set) var uncertain = false
    private(set) var failure: AppErrorMessage?
    @ObservationIgnored weak var workspace: FindingTrafficWorkspace?
    @ObservationIgnored private let store: FindingTrafficStore
    @ObservationIgnored private let onChanged: @MainActor (UUID) async -> Void
    init(store: FindingTrafficStore,onChanged: @escaping @MainActor (UUID) async -> Void) { self.store = store; self.onChanged = onChanged }
    var canMutate: Bool {
        workspace?.trafficControlsAvailable == true && !store.isMutating && store.canMutateSelected && store.unknownIDs.isEmpty &&
        !store.summary.isLoading && !store.summary.isStale && store.summary.value != nil
    }
    private func open(_ kind: FindingTrafficActionDialog.Kind, owner: UUID, version: Int64? = nil) -> Bool {
        guard let workspace, workspace.id == owner, workspace.trafficControlsAvailable,
              !store.summary.isLoading, !store.summary.isStale, let snapshot = store.summary.value,
              version == nil || snapshot.version == version else { return false }
        let context = FindingTrafficActionDialog(workspace:owner,owner:store.owner,unknownRevision:store.unknownRevision,
                                                version:snapshot.version,membership:snapshot.bindings.map(\.id),kind:kind)
        workspace.publishTrafficState {
            uncertain = false; failure = nil; roleDraft = nil; noteDraft = ""; dialog = context
        }
        return workspace.isActive && dialog?.id == context.id
    }
    @discardableResult func openEdit(_ id: String,owner: UUID,version: Int64? = nil) -> Bool {
        guard canMutate, let binding = store.summary.value?.bindings.first(where: { $0.id == id }), open(.edit(id),owner:owner,version:version), let workspace else { return false }
        workspace.publishTrafficState { roleDraft = FindingTrafficRole(rawValue:binding.role); noteDraft = binding.note }
        return workspace.isActive && dialog != nil
    }
    @discardableResult func openRemove(_ id: String,owner: UUID,version: Int64? = nil) -> Bool {
        guard canMutate, store.summary.value?.bindings.contains(where: { $0.id == id }) == true else { return false }
        return open(.remove(id),owner:owner,version:version)
    }
    @discardableResult func openMove(_ id: String,delta: Int,owner: UUID,version: Int64? = nil) -> Bool {
        guard canMutate, delta == -1 || delta == 1, var ids = store.summary.value?.bindings.map(\.id),
              let index = ids.firstIndex(of:id), ids.indices.contains(index+delta) else { return false }
        ids.swapAt(index,index+delta); return open(.reorder(ids),owner:owner,version:version)
    }
    @discardableResult func openAcknowledgement(owner: UUID) -> Bool {
        guard let id = workspace?.target.findingId, store.unknownIDs.contains(id) else { return false }
        return open(.acknowledge,owner:owner)
    }
    var canAcknowledge: Bool {
        guard let workspace, let id = workspace.target.findingId else { return false }
        return workspace.trafficControlsAvailable && !store.isMutating && store.unknownIDs.contains(id) && !store.summary.isLoading && !store.summary.isStale
    }
    private func current(_ context: FindingTrafficActionDialog) -> Bool {
        guard let workspace, workspace.confirmationControlsAvailable, workspace.id == context.workspace,
              store.owner == context.owner, !store.isMutating, !store.summary.isLoading, !store.summary.isStale,
              let summary = store.summary.value, summary.version == context.version,
              summary.bindings.map(\.id) == context.membership else { return false }
        if case .acknowledge = context.kind { return store.unknownRevision == context.unknownRevision }
        return store.unknownIDs.isEmpty && store.canMutateSelected
    }
    var canSubmit: Bool {
        guard !isSubmitting, !uncertain, let context = dialog, current(context) else { return false }
        if case .edit = context.kind { return roleDraft != nil }
        return true
    }
    func close(id: UUID) {
        guard !isSubmitting, dialog?.id == id, let workspace else { return }
        workspace.publishTrafficState { clear() }
    }
    @discardableResult func submit(id: UUID) async -> Bool {
        guard !Task.isCancelled, canSubmit, let context = dialog, context.id == id, let workspace else { return false }
        if case .acknowledge = context.kind {
            guard let findingID = workspace.target.findingId,
                  store.acknowledgeUnknown(findingID,owner:context.owner,revision:context.unknownRevision) else { return false }
            guard workspace.isActive, dialog?.id == context.id else { return false }
            workspace.publishTrafficState { clear() }; return true
        }
        let change: FindingTrafficChange
        switch context.kind {
        case .edit(let binding):
            guard let role = roleDraft else { return false }
            change = .edit(bindingID:binding,role:role,note:noteDraft)
        case .remove(let binding): change = .remove(bindingID:binding)
        case .reorder(let ids): change = .reorder(ids)
        case .acknowledge: return false
        }
        workspace.publishTrafficState { isSubmitting = true; failure = nil }
        defer {
            workspace.scrubStoppedTraffic()
            workspace.publishTrafficState { isSubmitting = false }
        }
        guard workspace.isActive, dialog?.id == context.id, store.owner == context.owner else { return false }
        let result = await store.apply(change,owner:context.owner)
        guard workspace.isActive, dialog?.id == context.id, store.owner == context.owner else { return false }
        switch result {
        case .confirmed:
            await onChanged(workspace.id)
            guard workspace.isActive, dialog?.id == context.id else { return false }
            workspace.clearTrafficPreview()
            workspace.publishTrafficState { clear() }; return true
        case .unconfirmed:
            workspace.publishTrafficState { uncertain = true; failure = store.mutationFailure }
        case .invalidInput:
            workspace.publishTrafficState { failure = store.mutationFailure }
        case .discarded:
            workspace.publishTrafficState { uncertain = !store.unknownIDs.isEmpty }
        case .notStarted: break
        }
        return false
    }
    func stop() { clear() }
    private func clear() { dialog = nil; roleDraft = nil; noteDraft = ""; failure = nil; uncertain = false }
}
