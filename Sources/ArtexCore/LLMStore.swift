import Foundation
import Observation

@MainActor @Observable public final class LLMStore {
    public private(set) var profiles: [LLMProfile] = []
    public private(set) var pool: LLMPoolStatus?
    public private(set) var retryPolicy: LLMRetryPolicy?
    public private(set) var isLoading = false
    public private(set) var isMutating = false
    public private(set) var hasLoaded = false
    public var error: String? { failure?.text(language: .japanese) }
    public private(set) var failure: AppErrorMessage?
    public var notice: String? { noticeKey.map { AppStrings.text($0, language: .japanese) } }
    public private(set) var noticeKey: AppStringKey?
    @ObservationIgnored public let service: LLMService
    public init(service: LLMService) { self.service = service }
    public func load() async {
        guard !isMutating else { return }
        await reload()
    }
    private func reload() async {
        guard !isLoading else { return }
        isLoading = true; failure = nil
        defer { isLoading = false }
        do {
            let profiles = try await service.profiles()
            let pool = try await service.pool()
            let retry = try await service.retry()
            self.profiles = profiles; self.pool = pool; retryPolicy = retry; hasLoaded = true
        } catch { self.failure = AppErrorMessage(error) }
    }
    public func refreshPool() async {
        guard !isLoading, !isMutating else { return }
        do { pool = try await service.pool() }
        catch { self.failure = AppErrorMessage(error) }
    }
    private func perform(_ message: AppStringKey, operation: () async throws -> Void) async -> Bool {
        guard !isMutating, !isLoading else { return false }
        isMutating = true; failure = nil; noticeKey = nil
        defer { isMutating = false }
        do {
            try await operation()
            noticeKey = message
            // A confirmed mutation must not appear to fail merely because reload failed.
            // Otherwise retrying a create could duplicate a profile.
            await reload()
            return true
        } catch { self.failure = AppErrorMessage(error); return false }
    }
    public func save(_ draft: LLMProfileDraft) async -> Bool {
        await perform(.llmNoticeSaved) { _ = try await service.save(draft) }
    }
    public func activate(_ profile: LLMProfile) async {
        _ = await perform(.llmNoticeActivated) { try await service.activate(id: profile.id) }
    }
    public func delete(_ profile: LLMProfile) async {
        _ = await perform(.llmNoticeDeleted) { try await service.delete(id: profile.id, isActive: profile.isDefault) }
    }
    public func setRotation(enabled: Bool? = nil, bindFallback: Bool? = nil) async {
        _ = await perform(.llmNoticeRotationSaved) { try await service.setRotation(enabled: enabled, bindFallback: bindFallback) }
    }
    public func resetPool(id: String? = nil) async {
        _ = await perform(.llmNoticePoolReset) { _ = try await service.resetPool(id: id) }
    }
    public func saveRetry(_ policy: LLMRetryPolicy) async -> Bool {
        await perform(.llmNoticeRetrySaved) { retryPolicy = try await service.saveRetry(policy) }
    }
}
