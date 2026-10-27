import Foundation
import Observation

public enum FindingTrafficMutationOutcome: Sendable {
    case notStarted, invalidInput, unconfirmed, discarded
    case confirmed(FindingTraffic)
}

/// Window-owned traffic state. Reads never acknowledge an uncertain write or launch another command.
@MainActor @Observable public final class FindingTrafficStore {
    public let summary = FindingReadState<FindingTraffic>()
    public let detail = FindingReadState<FindingTrafficDetail>()
    public let body = FindingReadState<FindingEvidencePreview>()
    public private(set) var owner = UUID()
    public private(set) var selectedBindingID: String?
    public private(set) var bodySide: FindingEvidenceSide = .response
    public private(set) var bodyOffset: Int64 = 0
    public private(set) var isActive = true
    public var isMutating: Bool { write != nil }
    public private(set) var unknownIDs = Set<String>()
    public private(set) var unknownRevision = UUID()
    public private(set) var lastConfirmation: FindingTraffic?
    public private(set) var mutationFailure: AppErrorMessage?
    public private(set) var selectionFailure: AppErrorMessage?
    @ObservationIgnored private let service: FindingTrafficService
    @ObservationIgnored private var target: FindingRecord?
    @ObservationIgnored private var context: String?
    @ObservationIgnored private var session = UUID()
    @ObservationIgnored private var activity = UUID()
    private var write: Ticket?
    private final class Ticket {
        let id = UUID()
        let session, activity, owner: UUID
        let findingID: String
        var handedOff = false
        init(session: UUID,activity: UUID,owner: UUID,findingID: String) {
            self.session = session; self.activity = activity; self.owner = owner; self.findingID = findingID
        }
    }
    public init(service: FindingTrafficService) { self.service = service }

    @discardableResult public func select(_ target: FindingRecord?,contextTaskID: String? = nil) -> Bool {
        guard isActive, !isMutating, !Task.isCancelled else { return false }
        let context: String?
        do {
            context = try contextTaskID.map(FindingWire.canonicalID)
            if let context {
                guard let target, target.inherited ? target.taskId != context : target.taskId == context else { throw FindingInputError.readOnly }
            }
        } catch { selectionFailure = AppErrorMessage(error); return false }
        self.target = target; self.context = context; owner = UUID(); selectionFailure = nil
        summary.invalidate(clear:true); clearBinding(); lastConfirmation = nil; mutationFailure = nil
        return true
    }
    @discardableResult public func selectBinding(_ id: String?,owner: UUID) -> Bool {
        guard readable(owner), !isMutating else { return false }
        let selected: String?
        do {
            selected = try id.map(FindingWire.canonicalID)
            if let selected { guard summary.value?.bindings.contains(where:{$0.id == selected}) == true else { throw FindingInputError.invalidID } }
        } catch { selectionFailure = AppErrorMessage(error); return false }
        selectedBindingID = selected; resetPreview(); selectionFailure = nil; return true
    }
    @discardableResult public func configureBody(side: FindingEvidenceSide,offset: Int64,owner: UUID) -> Bool {
        guard readable(owner), !isMutating, let snapshot = currentDetail(), offset >= 0,
              offset <= length(snapshot,side) else { return false }
        if bodySide != side || bodyOffset != offset {
            bodySide = side; bodyOffset = offset; body.invalidate(clear:true)
        }
        return true
    }
    @discardableResult public func nextBodyPage(owner: UUID) -> Bool {
        guard !body.isLoading, !body.isStale, let value = body.value, value.truncated else { return false }
        return configureBody(side:bodySide,offset:value.nextOffset,owner:owner)
    }
    public func refreshSummary() async {
        guard readable(owner), !isMutating, let id = target?.findingId else { return }
        let context = context
        if await summary.refresh({[service] in try await service.list(findingID:id,contextTaskID:context)}) { reconcile(clear:false) }
    }
    public func refreshDetail() async {
        guard readable(owner), !isMutating, let id = target?.findingId, let selected = selectedBindingID,
              let binding = summary.value?.bindings.first(where:{$0.id == selected}) else { return }
        let context = context
        _ = await detail.refresh { [service] in
            let value = try await service.detail(findingID:id,bindingID:selected,contextTaskID:context)
            guard Data(value.binding.snapshotId.utf8) == Data(binding.snapshotId.utf8) else { throw BackendAPIError.invalidResponse }
            return value
        }
    }
    public func refreshBody() async {
        guard readable(owner), !isMutating, let id = target?.findingId, let selected = selectedBindingID,
              let snapshot = currentDetail() else { return }
        let context = context, side = bodySide, offset = bodyOffset, total = length(snapshot,bodySide)
        guard offset <= total else { return }
        _ = await body.refresh { [service] in
            let value = try await service.body(findingID:id,bindingID:selected,side:side,offset:offset,contextTaskID:context)
            guard value.total == total else { throw BackendAPIError.invalidResponse }; return value
        }
    }
    public func apply(_ change: FindingTrafficChange,owner: UUID) async -> FindingTrafficMutationOutcome {
        guard readable(owner), !isMutating, unknownIDs.isEmpty, !summary.isLoading, !summary.isStale,
              let target, let snapshot = summary.value else { return .notStarted }
        let request: FindingTrafficWriteRequest
        do { request = try service.prepare(change,to:target,snapshot:snapshot,contextTaskID:context) }
        catch { mutationFailure = AppErrorMessage(error); return .invalidInput }
        let ticket = Ticket(session:session,activity:activity,owner:owner,findingID:request.owner)
        write = ticket; mutationFailure = nil; lastConfirmation = nil
        invalidateReads()
        defer { if write?.id == ticket.id { write = nil } }
        do {
            let value = try await service.execute(request) {
                guard ticket.session == self.session, ticket.activity == self.activity, ticket.owner == self.owner,
                      self.isActive, self.write?.id == ticket.id else { throw CancellationError() }
                ticket.handedOff = true
            }
            guard ticket.session == session else { return .discarded }
            guard ticket.activity == activity, isActive else { recordUnknown(ticket.findingID); return .discarded }
            try Task.checkCancellation()
            summary.acceptConfirmed(value); lastConfirmation = value; reconcile(clear:true); return .confirmed(value)
        } catch {
            guard ticket.session == session else { return .discarded }
            guard ticket.handedOff else { return .notStarted }
            recordUnknown(ticket.findingID)
            guard ticket.activity == activity, isActive else { return .discarded }
            mutationFailure = AppErrorMessage(error); return .unconfirmed
        }
    }
    @discardableResult public func acknowledgeUnknown(_ id: String,owner: UUID,revision: UUID) -> Bool {
        guard readable(owner), !isMutating, target?.findingId == id, revision == unknownRevision,
              unknownIDs.contains(id) else { return false }
        unknownIDs.remove(id); unknownRevision = UUID(); if unknownIDs.isEmpty { mutationFailure = nil }; return true
    }
    public func stop() {
        isActive = false; activity = UUID(); owner = UUID(); invalidateReads(); lastConfirmation = nil
        if let write, write.handedOff { recordUnknown(write.findingID) }
    }
    public func resume() {
        guard !isActive else { return }
        isActive = true; activity = UUID(); owner = UUID(); invalidateReads()
    }
    public func reset() {
        stop(); session = UUID(); write = nil; target = nil; context = nil
        summary.invalidate(clear:true); clearBinding(); unknownIDs = []; unknownRevision = UUID()
        mutationFailure = nil; selectionFailure = nil; lastConfirmation = nil
    }
    private func readable(_ owner: UUID) -> Bool { isActive && self.owner == owner && !Task.isCancelled }
    private func invalidateReads() { summary.invalidate(); detail.invalidate(); body.invalidate() }
    private func resetPreview() { detail.invalidate(clear:true); body.invalidate(clear:true); bodySide = .response; bodyOffset = 0 }
    private func clearBinding() { selectedBindingID = nil; resetPreview() }
    private func recordUnknown(_ id: String) { if unknownIDs.insert(id).inserted { unknownRevision = UUID() } }
    private func currentDetail() -> FindingTrafficSnapshot? {
        guard !detail.isStale, let detail = detail.value, detail.binding.id == selectedBindingID else { return nil }
        return detail.binding.snapshot
    }
    private func length(_ snapshot: FindingTrafficSnapshot,_ side: FindingEvidenceSide) -> Int64 {
        side == .request ? snapshot.requestLength : snapshot.responseLength
    }
    private func reconcile(clear: Bool) {
        guard let selected = selectedBindingID else { return }
        guard summary.value?.bindings.contains(where:{$0.id == selected}) == true else { clearBinding(); return }
        if clear { resetPreview() } else { detail.invalidate(); body.invalidate() }
    }
}
