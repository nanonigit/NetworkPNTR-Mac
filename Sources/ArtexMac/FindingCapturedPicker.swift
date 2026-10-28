import ArtexCore
import Foundation
import Observation

struct CapturedPickerFilterTicket: Hashable {
    let picker: UUID
    let host, keyword: Data
    let method: String?
}

/// One picker owns byte-based filter drafts and the core query/selection generations.
@MainActor @Observable final class FindingCapturedPicker: Identifiable {
    let id = UUID()
    let store: CapturedTrafficPickerStore
    var hostDraft = ""
    var keywordDraft = ""
    var methodDraft: CapturedHTTPMethod?
    private(set) var isActive = true
    private(set) var isSubmitting = false
    private(set) var failure: AppErrorMessage?
    @ObservationIgnored private weak var workspace: FindingTrafficWorkspace?
    @ObservationIgnored private var stopping = false
    init(workspace: FindingTrafficWorkspace,service: CapturedTrafficService) {
        self.workspace = workspace; store = CapturedTrafficPickerStore(service:service,evidence:workspace.store)
    }
    private var current: Bool {
        guard let workspace else { return false }
        return isActive && !stopping && workspace.picker?.id == id && workspace.pickerControlsAvailable && store.isCurrent && !Task.isCancelled
    }
    var filterTicket: CapturedPickerFilterTicket { .init(picker:id,host:Data(hostDraft.utf8),keyword:Data(keywordDraft.utf8),method:methodDraft?.rawValue) }
    var filtersCurrent: Bool {
        Data(store.query.host.utf8) == Data(hostDraft.utf8) && Data(store.query.keyword.utf8) == Data(keywordDraft.utf8) && store.query.method == methodDraft
    }
    var canEditFilters: Bool { current && !isSubmitting }
    var canSelect: Bool { canEditFilters && filtersCurrent && !store.catalog.isLoading && !store.catalog.isStale && store.catalog.value?.isUnavailable == false }
    var canBind: Bool { canSelect && store.canBind }
    func isBound(_ source: String) -> Bool {
        workspace?.store.summary.value?.bindings.contains { Data($0.snapshot.sourceTrafficId.utf8) == Data(source.utf8) } == true
    }
    func isSelected(_ source: String,owner: UUID) -> Bool {
        current && store.owner == owner && (isBound(source) || store.selectedIDs.contains { Data($0.utf8) == Data(source.utf8) })
    }
    func updateDraft(_ update: () -> Void) {
        guard canEditFilters, let workspace else { return }
        workspace.publishTrafficState(update)
    }
    func debounce(_ ticket: CapturedPickerFilterTicket) async {
        do { try await Task.sleep(for:.milliseconds(250)); try Task.checkCancellation() } catch { return }
        await applyFilters(ticket)
    }
    func applyFilters(_ ticket: CapturedPickerFilterTicket) async {
        guard canEditFilters, ticket == filterTicket, let workspace else { return }
        var query = CapturedTrafficQuery(); query.host = hostDraft; query.keyword = keywordDraft; query.method = methodDraft
        var accepted = false
        workspace.publishTrafficState { accepted = store.configure(query,owner:store.owner); failure = nil }
        guard current, accepted, ticket == filterTicket else { return }
        await store.refreshCatalog()
    }
    func reload(owner: UUID) async {
        guard canEditFilters, filtersCurrent, store.owner == owner else { return }
        await store.refreshCatalog()
    }
    func page(forward: Bool,owner: UUID) async {
        guard canSelect, store.owner == owner, let workspace else { return }
        var accepted = false
        workspace.publishTrafficState { accepted = forward ? store.nextPage(owner:owner) : store.previousPage(owner:owner) }
        if current, accepted { await store.refreshCatalog() }
    }
    @discardableResult func toggle(_ source: String,selected: Bool,owner: UUID) -> Bool {
        guard canSelect, let workspace else { return false }
        var accepted = false
        workspace.publishTrafficState { accepted = store.toggle(id:source,selected:selected,owner:owner) }
        return current && accepted
    }
    @discardableResult func selectPage(_ selected: Bool,owner: UUID) -> Bool {
        guard canSelect, let workspace else { return false }
        var accepted = false
        workspace.publishTrafficState { accepted = store.selectPage(selected,owner:owner) }
        return current && accepted
    }
    @discardableResult func clearSelection(owner: UUID) -> Bool {
        guard canEditFilters, let workspace else { return false }
        var accepted = false
        workspace.publishTrafficState { accepted = store.clearSelection(owner:owner) }
        return current && accepted
    }
    func selectPreview(_ source: String,owner: UUID) async {
        guard canSelect, let workspace else { return }
        var accepted = false
        workspace.publishTrafficState { accepted = store.selectPreview(id:source,owner:owner) }
        if current, accepted { await store.refreshPreview() }
    }
    func closePreview(_ source: String,owner: UUID) {
        guard canEditFilters, store.selectedPreviewID.map({Data($0.utf8)}) == Data(source.utf8), let workspace else { return }
        workspace.publishTrafficState { _ = store.selectPreview(id:nil,owner:owner) }
    }
    @discardableResult func bind(owner: UUID) async -> Bool {
        guard canBind, store.owner == owner, let workspace else { return false }
        workspace.publishTrafficState { isSubmitting = true; failure = nil }
        defer {
            workspace.scrubStoppedTraffic()
            workspace.publishTrafficState { isSubmitting = false }
        }
        guard current, store.owner == owner else { return false }
        let result = await store.bind(owner:owner)
        guard current, store.owner == owner else { return false }
        switch result {
        case .confirmed:
            await workspace.pickerMutationConfirmed()
            guard current, store.owner == owner else { return false }
            workspace.closePicker(id:id,confirmed:true); return true
        case .invalidInput, .unconfirmed:
            workspace.publishTrafficState { failure = store.failure }
        case .discarded, .notStarted: break
        }
        return false
    }
    func stop() {
        guard !stopping, isActive else { return }
        stopping = true
        defer { stopping = false }
        isActive = false; store.stop(); hostDraft = ""; keywordDraft = ""; methodDraft = nil; failure = nil
    }
}
