import Foundation
import Observation

/// Binding action state for the standalone Traffic workflow; callers retain it across modal visits.
@MainActor @Observable public final class TrafficBindingStore {
    public private(set) var owner = UUID()
    public private(set) var requestID = UUID()
    public private(set) var isActive = true
    public private(set) var target: FindingRecord?
    public private(set) var sourceIDs: [String] = []
    public private(set) var summary: FindingTraffic?
    public private(set) var isLoading = false
    public private(set) var isStale = true
    public private(set) var failure: AppErrorMessage?
    public private(set) var lastConfirmation: FindingTraffic?
    public private(set) var hasUnknownOutcome = false
    public private(set) var unknownRevision = UUID()
    public var isMutating: Bool { write != nil }
    public var canBind: Bool {
        ready && !hasUnknownOutcome && !consumed && !isLoading && !isStale && target?.canMutate == true
            && !sourceIDs.isEmpty && summary?.findingId == selectedID
    }
    public var canAcknowledgeUnknown: Bool {
        ready && hasUnknownOutcome && !isLoading && !isStale && summary?.findingId == unknownTarget
            && recoveredOwner == owner && recoveredRevision == unknownRevision
    }
    @ObservationIgnored private let service: FindingTrafficService
    @ObservationIgnored private var session = UUID()
    @ObservationIgnored private var period = UUID()
    @ObservationIgnored private var changing = false
    @ObservationIgnored private var queuedStop = false
    @ObservationIgnored private var queuedReset = false
    @ObservationIgnored private var lifecycle = Lifecycle.none
    @ObservationIgnored private var readTicket: UUID?
    @ObservationIgnored private var selectedID: String?
    @ObservationIgnored private var unknownTarget: String?
    @ObservationIgnored private var unknownMinimum: Int64 = 0
    @ObservationIgnored private var unknownTicket: UUID?
    private var recoveredOwner: UUID?
    private var recoveredRevision: UUID?
    private var consumed = false
    private var write: Ticket?
    private enum Lifecycle { case none, stopping, resetting }
    private final class Ticket {
        let id = UUID()
        let session, period, owner: UUID
        let request: FindingTrafficWriteRequest
        var sent = false, revoked = false
        init(session: UUID, period: UUID, owner: UUID, request: FindingTrafficWriteRequest) {
            self.session = session; self.period = period; self.owner = owner; self.request = request
        }
    }
    public init(service: FindingTrafficService) { self.service = service }
    private var ready: Bool { isActive && !changing && lifecycle == .none && write == nil && !Task.isCancelled }
    private func current(_ expected: UUID) -> Bool { ready && owner == expected }
    private func same(_ ticket: Ticket) -> Bool {
        isActive && lifecycle == .none && !queuedStop && !queuedReset && !ticket.revoked
            && owner == ticket.owner && session == ticket.session && period == ticket.period
    }
    private func owns(_ ticket: Ticket) -> Bool { !changing && same(ticket) && write === ticket }
    private func update(_ body: () -> Void) {
        precondition(!changing)
        changing = true; body(); changing = false; drain()
    }
    private func drain() {
        guard !changing, lifecycle == .none else { return }
        if queuedReset { queuedReset = false; queuedStop = false; resetSession() }
        else if queuedStop { queuedStop = false; _ = stop() }
    }
    private func clearProof() { recoveredOwner = nil; recoveredRevision = nil }
    @discardableResult public func select(_ target: FindingRecord, sourceIDs: [String], owner expected: UUID) -> Bool {
        guard current(expected), !hasUnknownOutcome else { return false }
        let handle: String
        do {
            guard target.canMutate, let id = target.findingId else { throw FindingInputError.readOnly }
            handle = try FindingWire.canonicalID(id)
            guard !sourceIDs.isEmpty, Set(sourceIDs.map { Data($0.utf8) }).count == sourceIDs.count else { throw FindingInputError.patch }
            for id in sourceIDs {
                try CapturedTrafficWire.validateID(id)
                guard !FindingWire.serverTrim(id).isEmpty else { throw FindingInputError.patch }
            }
            struct Body: Encodable { let trafficRefs: [FindingTrafficRef] }
            let body = try BackendJSONCoding.encode(Body(trafficRefs: sourceIDs.map { .init(trafficId: $0) }))
            guard body.count <= 1024 * 1024 else { throw FindingInputError.bodyLimit }
        } catch { update { failure = AppErrorMessage(error) }; return false }
        let next = UUID()
        update {
            self.target = target; self.sourceIDs = sourceIDs; selectedID = handle
            owner = next; requestID = UUID(); consumed = false; readTicket = nil; isLoading = false
            summary = nil; isStale = true; failure = nil; lastConfirmation = nil; clearProof()
        }
        return current(next)
    }
    public func refresh(owner expected: UUID) async {
        guard current(expected), !hasUnknownOutcome, let selectedID else { return }
        await read(id: selectedID, minimum: 0, owner: expected, revision: nil)
    }
    /// Explicit recovery reads only the private canonical handle from the uncertain operation.
    public func recover(owner expected: UUID) async {
        guard current(expected), hasUnknownOutcome, let unknownTarget else { return }
        await read(id: unknownTarget, minimum: unknownMinimum, owner: expected, revision: unknownRevision)
    }
    private func read(id: String, minimum: Int64, owner expected: UUID, revision: UUID?) async {
        guard current(expected), !isLoading else { return }
        let token = UUID(), epoch = session, activity = period
        update { readTicket = token; isLoading = true; clearProof() }
        func valid() -> Bool { current(expected) && readTicket == token && session == epoch && period == activity }
        defer { if readTicket == token { update { readTicket = nil; isLoading = false } } }
        guard valid() else { return }
        do {
            let value = try await service.list(findingID: id)
            guard valid() else { return }
            guard value.version >= minimum else { throw BackendAPIError.invalidResponse }
            update {
                summary = value; isStale = false; failure = nil
                if let revision, hasUnknownOutcome, revision == unknownRevision {
                    recoveredOwner = expected; recoveredRevision = revision
                }
            }
        } catch {
            guard valid() else { return }
            update { isStale = true; if !(error is CancellationError) { failure = AppErrorMessage(error) } }
        }
    }
    public func bind(id: UUID, owner expected: UUID, onDispatch: @MainActor () throws -> Void = {}) async -> FindingTrafficMutationOutcome {
        guard current(expected), canBind, requestID == id, let target, let summary else { return .notStarted }
        let request: FindingTrafficWriteRequest
        do { request = try service.prepare(.bind(sourceIDs.map { .init(trafficId: $0) }), to: target, snapshot: summary) }
        catch { update { failure = AppErrorMessage(error) }; return .invalidInput }
        let required = Set(sourceIDs.map { Data($0.utf8) })
        let ticket = Ticket(session: session, period: period, owner: expected, request: request)
        update { write = ticket; consumed = true; lastConfirmation = nil; failure = nil; isStale = true; clearProof() }
        defer { if write === ticket { update { write = nil } } }
        guard owns(ticket), !Task.isCancelled else { return .notStarted }
        do {
            let receipt = try await service.execute(request) {
                try onDispatch()
                guard self.owns(ticket), !Task.isCancelled else { throw CancellationError() }
                ticket.sent = true
            }
            let present = Set(receipt.bindings.map { Data($0.snapshot.sourceTrafficId.utf8) })
            guard required.isSubset(of: present) else { throw BackendAPIError.invalidResponse }
            guard owns(ticket), !Task.isCancelled else { update { markUnknown(ticket) }; return .discarded }
            update { self.summary = receipt; isStale = false; lastConfirmation = receipt }
            guard owns(ticket) else { return .discarded }
            return finish(.confirmed(receipt), ticket: ticket)
        } catch {
            guard ticket.sent else { return .notStarted }
            update {
                markUnknown(ticket)
                if same(ticket), !Task.isCancelled, !(error is CancellationError) { failure = AppErrorMessage(error) }
            }
            return finish(.unconfirmed, ticket: ticket)
        }
    }
    private func finish(_ result: FindingTrafficMutationOutcome, ticket: Ticket) -> FindingTrafficMutationOutcome {
        if write === ticket { update { write = nil } }
        guard same(ticket), !Task.isCancelled else { return .discarded }
        return result
    }
    private func markUnknown(_ ticket: Ticket) {
        if unknownTicket != ticket.id { unknownTicket = ticket.id; unknownRevision = UUID() }
        hasUnknownOutcome = true; unknownTarget = ticket.request.owner; unknownMinimum = ticket.request.previousVersion; clearProof()
    }
    @discardableResult public func acknowledge(owner expected: UUID, revision: UUID) -> Bool {
        guard current(expected), canAcknowledgeUnknown, revision == unknownRevision else { return false }
        update {
            hasUnknownOutcome = false; unknownTarget = nil; unknownMinimum = 0; unknownTicket = nil
            unknownRevision = UUID(); requestID = UUID(); consumed = false; failure = nil; clearProof()
        }
        return current(expected)
    }
    @discardableResult public func stop(ifOwnedBy expected: UUID? = nil) -> Bool {
        guard expected == nil || owner == expected, lifecycle != .resetting else { return false }
        if changing || lifecycle == .stopping {
            if lifecycle == .none { queuedStop = true; write?.revoked = true }; return true
        }
        guard isActive else { return false }; deactivate(reset: false); return true
    }
    public func resetSession() {
        guard lifecycle != .resetting else { return }
        if changing || lifecycle == .stopping { queuedReset = true; queuedStop = false; write?.revoked = true; return }
        deactivate(reset: true)
    }
    private func deactivate(reset: Bool) {
        lifecycle = reset ? .resetting : .stopping
        update {
            if let write, write.sent { markUnknown(write) }
            write?.revoked = true
            if reset { session = UUID() }
            period = UUID(); isActive = false; owner = UUID(); requestID = UUID(); consumed = false
            readTicket = nil; isLoading = false; target = nil; selectedID = nil; sourceIDs = []
            summary = nil; isStale = true; failure = nil; lastConfirmation = nil; clearProof()
        }
        lifecycle = .none; drain()
    }
    public func resume() {
        guard !isActive, !changing, lifecycle == .none, !Task.isCancelled else { return }
        update { period = UUID(); owner = UUID(); isActive = true }
    }
}
