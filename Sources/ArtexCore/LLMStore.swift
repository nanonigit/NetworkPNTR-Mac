import Foundation
import Observation

@MainActor @Observable public final class LLMStore {
    public private(set) var profiles: [LLMProfile] = []
    public private(set) var pool: LLMPoolStatus?
    public private(set) var retryPolicy: LLMRetryPolicy?
    public var isLoading: Bool { read != nil }
    public var isMutating: Bool { write != nil }
    public private(set) var isActive = true
    public private(set) var hasLoaded = false
    public private(set) var unknownRevision: UUID?
    public var canAcknowledgeUnknown: Bool {
        isActive && !isLoading && !isMutating && unknownRevision != nil && reviewedRevision == unknownRevision
    }
    public var error: String? { failure?.text(language: .japanese) }
    public private(set) var failure: AppErrorMessage?
    public var notice: String? { noticeKey.map { AppStrings.text($0, language: .japanese) } }
    public private(set) var noticeKey: AppStringKey?
    @ObservationIgnored public let service: LLMService
    @ObservationIgnored private var activity = UUID()
    @ObservationIgnored private var acquiring = false
    @ObservationIgnored private var stopping = false
    @ObservationIgnored private var resuming = false
    @ObservationIgnored private var stopAfterResume = false
    @ObservationIgnored private var reviewedRevision: UUID?
    private var read: ReadTicket?
    private var write: WriteTicket?
    private struct ReadTicket {
        let id = UUID()
        let activity: UUID
    }
    private final class WriteTicket {
        let id = UUID()
        let activity: UUID
        var handedOff = false
        var confirmed = false
        var recordedUnknown = false
        init(activity: UUID) { self.activity = activity }
    }
    public init(service: LLMService) { self.service = service }

    public func load() async {
        guard !isMutating, !acquiring else { return }
        await reload()
    }
    private func owns(_ ticket: ReadTicket) -> Bool {
        isActive && ticket.activity == activity && read?.id == ticket.id && !Task.isCancelled
    }
    private func beginRead() -> ReadTicket? {
        guard isActive, !isLoading, !acquiring, !Task.isCancelled else { return nil }
        acquiring = true
        defer { acquiring = false }
        let ticket = ReadTicket(activity: activity)
        read = ticket
        guard owns(ticket) else {
            if read?.id == ticket.id { read = nil }
            return nil
        }
        failure = nil
        return ticket
    }
    private func reload() async {
        guard let ticket = beginRead() else { return }
        let revision = unknownRevision
        reviewedRevision = nil
        defer { if read?.id == ticket.id { read = nil } }
        do {
            guard owns(ticket) else { return }
            let profiles = try await service.profiles()
            guard owns(ticket) else { return }
            let pool = try await service.pool()
            guard owns(ticket) else { return }
            let retry = try await service.retry()
            guard owns(ticket) else { return }
            self.profiles = profiles; self.pool = pool; retryPolicy = retry; hasLoaded = true
            if owns(ticket), !isMutating, revision == unknownRevision { reviewedRevision = revision }
        } catch {
            guard owns(ticket), !(error is CancellationError) else { return }
            failure = AppErrorMessage(error)
        }
    }
    public func refreshPool() async {
        guard !isMutating, let ticket = beginRead() else { return }
        defer { if read?.id == ticket.id { read = nil } }
        do {
            guard owns(ticket) else { return }
            let value = try await service.pool()
            guard owns(ticket) else { return }
            pool = value
        } catch {
            guard owns(ticket), !(error is CancellationError) else { return }
            failure = AppErrorMessage(error)
        }
    }
    private func owns(_ ticket: WriteTicket) -> Bool {
        isActive && ticket.activity == activity && write?.id == ticket.id && !Task.isCancelled
    }
    private func recordUnknown(_ ticket: WriteTicket) {
        guard ticket.handedOff, !ticket.confirmed, !ticket.recordedUnknown else { return }
        ticket.recordedUnknown = true; reviewedRevision = nil; unknownRevision = UUID()
    }
    @discardableResult public func acknowledgeUnknown(revision: UUID) -> Bool {
        guard !acquiring, canAcknowledgeUnknown, revision == unknownRevision else { return false }
        reviewedRevision = nil; unknownRevision = nil; failure = nil
        return true
    }
    public func stop() {
        if resuming { stopAfterResume = true; return }
        guard !stopping, isActive else { return }
        stopping = true
        defer { stopping = false }
        isActive = false; activity = UUID(); read = nil; noticeKey = nil; reviewedRevision = nil
        if let write { recordUnknown(write) }
    }
    public func resume() {
        guard !stopping, !resuming, !isActive else { return }
        resuming = true
        activity = UUID(); isActive = true
        resuming = false
        if stopAfterResume { stopAfterResume = false; stop() }
    }
    private func perform(_ message: AppStringKey,
                         operation: (@MainActor () throws -> Void) async throws -> LLMRetryPolicy?) async -> Bool {
        guard isActive, !isMutating, !isLoading, !acquiring, unknownRevision == nil, !Task.isCancelled else { return false }
        acquiring = true
        let ticket = WriteTicket(activity: activity)
        write = ticket
        acquiring = false
        defer { if write?.id == ticket.id { write = nil } }
        guard owns(ticket) else { return false }
        failure = nil; noticeKey = nil
        do {
            let retry = try await operation {
                try Task.checkCancellation()
                guard self.owns(ticket) else { throw CancellationError() }
                ticket.handedOff = true
            }
            guard owns(ticket) else { recordUnknown(ticket); return false }
            ticket.confirmed = true
            if let retry { retryPolicy = retry }
            noticeKey = message
            // A confirmed mutation stays confirmed when only its subsequent read fails.
            await reload()
            return true
        } catch {
            recordUnknown(ticket)
            guard owns(ticket), !(error is CancellationError) else { return false }
            failure = AppErrorMessage(error)
            return false
        }
    }
    public func save(_ draft: LLMProfileDraft) async -> Bool {
        await perform(.llmNoticeSaved) { callback in _ = try await service.save(draft, onDispatch: callback); return nil }
    }
    public func activate(_ profile: LLMProfile) async {
        _ = await perform(.llmNoticeActivated) { callback in try await service.activate(id: profile.id, onDispatch: callback); return nil }
    }
    public func delete(_ profile: LLMProfile) async {
        _ = await perform(.llmNoticeDeleted) { callback in try await service.delete(id: profile.id, isActive: profile.isDefault, onDispatch: callback); return nil }
    }
    public func setRotation(enabled: Bool? = nil, bindFallback: Bool? = nil) async {
        guard enabled != nil || bindFallback != nil else { return }
        _ = await perform(.llmNoticeRotationSaved) { callback in try await service.setRotation(enabled: enabled, bindFallback: bindFallback, onDispatch: callback); return nil }
    }
    public func resetPool(id: String? = nil) async {
        _ = await perform(.llmNoticePoolReset) { callback in _ = try await service.resetPool(id: id, onDispatch: callback); return nil }
    }
    public func saveRetry(_ policy: LLMRetryPolicy) async -> Bool {
        await perform(.llmNoticeRetrySaved) { callback in try await service.saveRetry(policy, onDispatch: callback) }
    }
}
