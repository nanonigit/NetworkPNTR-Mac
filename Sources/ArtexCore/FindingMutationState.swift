import Foundation

public enum FindingConfirmedMutation: Sendable { case updated(FindingRecord), deleted(FindingDeletion) }
public enum FindingMutationOutcome: Sendable {
    case notStarted, invalidInput, unconfirmed, discarded
    case confirmed(FindingConfirmedMutation)
}
struct FindingMutationTicket {
    let id = UUID()
    let session: UUID
    let activity: UUID
    let findingID: String
}

extension FindingStore {
    /// All errors after handoff are uncertain: source PATCH can commit one field before another fails.
    public func update(_ target: FindingRecord,patch: FindingPatch,owner: UUID) async -> FindingMutationOutcome {
        guard canBegin(target,owner:owner) else { return .notStarted }
        do {
            let normalized = try patch.normalized()
            guard try BackendJSONCoding.encode(normalized).count <= 64 * 1024 else { throw FindingInputError.bodyLimit }
        } catch { mutationFailure = AppErrorMessage(error); return .invalidInput }
        return await perform(target,owner:owner) { [service] in .updated(try await service.update(target,patch:patch)) }
    }
    public func delete(_ target: FindingRecord,owner: UUID) async -> FindingMutationOutcome {
        await perform(target,owner:owner) { [service] in .deleted(try await service.delete(target)) }
    }
    @discardableResult public func acknowledgeUnknown(_ id: String,owner: UUID,revision: UUID) -> Bool {
        guard !isMutating, !Task.isCancelled, owner == sessionOwner, revision == unknownRevision, unknownIDs.contains(id) else { return false }
        unknownIDs.remove(id); unknownRevision = UUID(); if unknownIDs.isEmpty { mutationFailure = nil }; return true
    }
    private func canBegin(_ target: FindingRecord,owner: UUID) -> Bool {
        guard !isMutating, !Task.isCancelled, unknownIDs.isEmpty, owner == viewOwner, target.canMutate, let id = target.findingId else { return false }
        let available = visibleRecords + (detail.value.map{[$0]} ?? [])
        return available.contains{$0.canMutate && $0.findingId == id}
    }
    private func perform(_ target: FindingRecord,owner: UUID,
                         action: @MainActor () async throws -> FindingConfirmedMutation) async -> FindingMutationOutcome {
        guard canBegin(target,owner:owner), let id = target.findingId else { return .notStarted }
        let ticket = FindingMutationTicket(session:sessionOwner,activity:activityOwner,findingID:id)
        mutationTicket = ticket; isMutating = true; mutationFailure = nil; lastConfirmation = nil
        invalidateReads(includeStats:true)
        defer { if mutationTicket?.id == ticket.id { mutationTicket = nil; isMutating = false } }
        do {
            let confirmation = try await action()
            guard ticket.session == sessionOwner else { return .discarded }
            guard ticket.activity == activityOwner else { recordUnknown(ticket.findingID); return .discarded }
            // A service already checks post-dispatch cancellation; keep this handoff boundary explicit too.
            try Task.checkCancellation()
            apply(confirmation); lastConfirmation = confirmation; return .confirmed(confirmation)
        } catch {
            guard ticket.session == sessionOwner else { return .discarded }
            recordUnknown(ticket.findingID)
            guard ticket.activity == activityOwner else { return .discarded }
            mutationFailure = AppErrorMessage(error); return .unconfirmed
        }
    }
    private func recordUnknown(_ id: String) { unknownIDs.insert(id); unknownRevision = UUID() }
    private func apply(_ mutation: FindingConfirmedMutation) {
        let pages = [flat] + Array(groupPages.values)
        switch mutation {
        case .updated(let row):
            for state in pages {
                state.read.mutateCached { value in
                    var copy = value; copy.items = value.items.map{$0.findingId == row.findingId && !$0.inherited ? row : $0}; return copy
                }
            }
            if detail.value?.findingId == row.findingId, selectedDetail?.contextTaskID == nil, detail.value?.inherited == false { detail.mutateCached{_ in row} }
        case .deleted(let receipt):
            let id = String(receipt.id)
            for state in pages {
                state.read.mutateCached { value in
                    var copy = value; copy.items = value.items.filter{$0.findingId != id}
                    if copy.items.count != value.items.count { copy.total = max(0,value.total-1) }; return copy
                }
            }
            selectedIDs.remove(id)
            if selectedDetail?.id == id { selectedDetail = nil; detail.invalidate(clear:true) }
        }
    }
}
