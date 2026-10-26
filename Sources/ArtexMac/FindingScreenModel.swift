import ArtexCore
import Foundation
import Observation

struct FindingDialog: Identifiable {
    enum Kind { case edit(FindingRecord), status(FindingRecord,FindingStatus), delete(FindingRecord), acknowledge(String) }
    let id = UUID()
    let kind: Kind
    let viewOwner: UUID
    let sessionOwner: UUID
    let unknownRevision: UUID
}

/// One authenticated window owns drafts and immutable confirmation contexts.
@MainActor @Observable final class FindingScreenModel {
    static let preferenceKey = "findings.screen.preferences.v1"
    let store: FindingStore
    var searchDraft = ""
    var nameDraft = ""
    var classDraft = ""
    var severityDraft: FindingSeverity?
    private(set) var dialog: FindingDialog?
    private(set) var dialogUncertain = false
    private(set) var dialogFailure: AppErrorMessage?
    private(set) var isSubmitting = false
    @ObservationIgnored private let preferences: UserDefaults?
    @ObservationIgnored private var lifecycle = UUID()

    init(store: FindingStore,preferences: UserDefaults? = nil) {
        self.store = store; self.preferences = preferences
        if let data = preferences?.data(forKey:Self.preferenceKey), data.count <= 32768,
           let saved = try? JSONDecoder().decode(FindingScreenPreferences.self,from:data),
           let (view,query) = saved.validated(), store.configureFilters(query) { _ = store.setView(view) }
    }
    var busy: Bool { isSubmitting || store.isMutating }
    @discardableResult func configureFilters(_ query: FindingQuery) -> Bool {
        guard !busy, dialog == nil, store.configureFilters(query) else { return false }
        searchDraft = query.search; persist(); return true
    }
    @discardableResult func setView(_ value: FindingView) -> Bool {
        guard !busy, dialog == nil, store.setView(value) else { return false }; persist(); return true
    }
    @discardableResult func beginEdit(_ target: FindingRecord) -> Bool {
        guard canOpen(target) else { return false }
        open(.edit(target)); nameDraft = target.name; classDraft = target.vulnclass
        severityDraft = FindingSeverity(rawValue:target.severity)
        return true
    }
    @discardableResult func beginStatus(_ target: FindingRecord,status: FindingStatus) -> Bool {
        guard canOpen(target) else { return false }; open(.status(target,status)); return true
    }
    @discardableResult func beginDelete(_ target: FindingRecord) -> Bool {
        guard canOpen(target) else { return false }; open(.delete(target)); return true
    }
    @discardableResult func beginAcknowledgement(_ id: String) -> Bool {
        guard !busy, dialog == nil, store.unknownIDs.contains(id), !Task.isCancelled else { return false }
        open(.acknowledge(id)); return true
    }
    func close(dialogID: UUID) {
        guard !busy, dialog?.id == dialogID else { return }; clearDialog()
    }
    @discardableResult func submit(dialogID: UUID) async -> Bool {
        guard !busy, !dialogUncertain, !Task.isCancelled, let context = dialog, context.id == dialogID,
              context.sessionOwner == store.sessionOwner else { return false }
        switch context.kind {
        case .acknowledge(let id):
            guard store.acknowledgeUnknown(id,owner:context.sessionOwner,revision:context.unknownRevision) else { return false }
            clearDialog(); return true
        case .edit, .status, .delete:
            guard context.viewOwner == store.viewOwner else { return false }
        }
        let life = lifecycle
        isSubmitting = true; dialogFailure = nil
        defer { isSubmitting = false }
        let result: FindingMutationOutcome
        switch context.kind {
        case .edit(let row):
            result = await store.update(row,patch:.init(name:nameDraft,vulnclass:classDraft,severity:severityDraft),owner:context.viewOwner)
        case .status(let row,let status): result = await store.update(row,patch:.init(status:status),owner:context.viewOwner)
        case .delete(let row): result = await store.delete(row,owner:context.viewOwner)
        case .acknowledge: return false
        }
        guard life == lifecycle, dialog?.id == context.id, context.sessionOwner == store.sessionOwner else { return false }
        switch result {
        case .confirmed: clearDialog(); return true
        case .unconfirmed: dialogUncertain = true; dialogFailure = store.mutationFailure
        case .invalidInput: dialogFailure = store.mutationFailure
        case .discarded: dialogUncertain = !store.unknownIDs.isEmpty
        case .notStarted: break
        }
        return false
    }
    func stop() { lifecycle = UUID(); clearDialog(); store.stop() }
    func reset() { lifecycle = UUID(); clearDialog(); searchDraft = ""; store.reset() }

    private func canOpen(_ target: FindingRecord) -> Bool {
        guard !busy, dialog == nil, !Task.isCancelled, store.unknownIDs.isEmpty, target.canMutate else { return false }
        let rows: [FindingRecord]
        if store.view == .grouped {
            let visible = Set(store.groups.read.value?.items.map{$0.taskId ?? "__unassigned__"} ?? [])
            rows = store.expandedGroups.intersection(visible).flatMap{store.groupPages[$0]?.read.value?.items ?? []}
        } else { rows = store.flat.read.value?.items ?? [] }
        return (rows + (store.detail.value.map{[$0]} ?? [])).contains { $0.canMutate && $0.findingId == target.findingId }
    }
    private func open(_ kind: FindingDialog.Kind) {
        dialog = FindingDialog(kind:kind,viewOwner:store.viewOwner,sessionOwner:store.sessionOwner,unknownRevision:store.unknownRevision)
        dialogUncertain = false; dialogFailure = nil
    }
    private func clearDialog() {
        dialog = nil; dialogUncertain = false; dialogFailure = nil
        nameDraft = ""; classDraft = ""; severityDraft = nil
    }
    private func persist() {
        guard let preferences, let data = try? JSONEncoder().encode(FindingScreenPreferences(store:store)), data.count <= 32768 else { return }
        preferences.set(data,forKey:Self.preferenceKey)
    }
}
