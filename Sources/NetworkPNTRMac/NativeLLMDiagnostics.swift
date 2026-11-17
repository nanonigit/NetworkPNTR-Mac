#if DEBUG
import NetworkPNTRCore
import Foundation

/// Uses the same authenticated service as the native LLM screen, on the fixture VM only.
@MainActor enum NativeLLMDiagnostics {
    struct Snapshot {
        let activeID: String
        let profile: [String: Any]
        let policy: LLMRetryPolicy
    }
    static func run(session: AuthenticationSession, directory: URL) async throws -> Snapshot {
        let service = LLMService(client: AuthenticatedBackendClient(session: session))
        guard try await service.profiles().isEmpty else { throw RuntimeError.integrity("fresh LLM fixture database") }
        var negative = LLMProfileDraft(); negative.model = "fixture-no-external-request"
        do { _ = try await service.models(negative); throw RuntimeError.integrity("missing-key model query accepted") }
        catch BackendAPIError.validation { /* Expected backend ok:false, not a fabricated success. */ }
        do { _ = try await service.test(negative); throw RuntimeError.integrity("missing-key connection test accepted") }
        catch BackendAPIError.validation { /* No external request is necessary for this negative case. */ }
        var a = LLMProfileDraft()
        a.name = "Fixture OpenAI"; a.model = "fixture-no-request"; a.format = .openai
        a.baseUrl = "https://api.example.invalid/v1"; a.apiKey = "fixture-non-live-credential-0000"
        a.ratePerSecond = 2.5; a.ratePerMinute = 30; a.contextWindowK = 64; a.priority = 3
        a.streaming = false; a.maxTokens = 256; a.maxTokensField = "max_completion_tokens"
        a.thinkingType = "enabled"; a.reasoningEffort = "high"; a.sessionHeaderKey = "X-NetworkPNTR-Session"
        a.retry.connect = LLMRetryRule(attempts: -1, intervalMs: 0)
        a.retry.empty = LLMRetryRule(attempts: 2, intervalMs: 1234)
        a.retry.stream = LLMRetryRule(attempts: 1, intervalMs: 500)
        let id = try await service.save(a)
        var b = LLMProfileDraft(); b.name = "Fixture Anthropic"; b.model = "fixture-anthropic"
        let other = try await service.save(b)
        var c = LLMProfileDraft(); c.name = "Fixture Responses"; c.model = "fixture-responses"; c.format = .openaiResponses
        c.priority = 9; c.poolExclude = true
        let excluded = try await service.save(c)
        let created = try await service.profiles()
        guard created.count == 3, Set(created.map(\.format)).count == 3,
              let original = created.first(where: { $0.id == String(id) }), original.apiKeyHint?.isEmpty == false,
              original.streaming == false, !original.isDefault else { throw RuntimeError.integrity("three-format profile creation") }
        var edited = try LLMProfileDraft(profile: original)
        guard edited.apiKey.isEmpty else { throw RuntimeError.integrity("stored key entered edit form") }
        edited.name = "Fixture OpenAI edited"; edited.model = "fixture-edited"; edited.ratePerMinute = 60
        _ = try await service.save(edited)
        let updated = try await service.profiles()
        guard let saved = updated.first(where: { $0.id == String(id) }), saved.apiKeyHint == original.apiKeyHint,
              saved.streaming == false, saved.name == edited.name, saved.model == edited.model else { throw RuntimeError.integrity("blank-key edit persistence") }
        try await service.activate(id: String(id))
        let protectedDelete = try await session.authenticatedRequest(method: "DELETE", path: "/api/llm/profiles/\(id)")
        guard protectedDelete.status == 409 else { throw RuntimeError.integrity("active profile deletion protection") }
        try await service.setRotation(enabled: true, bindFallback: true)
        let chain = try await service.pool()
        guard chain.enabled, chain.bindFallback, chain.chain.first?.profileId == String(id),
              chain.chain.contains(where: { $0.profileId == String(excluded) && $0.excluded }) else { throw RuntimeError.integrity("rotation chain and exclusion") }
        _ = try await service.resetPool(id: String(id)); _ = try await service.resetPool()
        var policy = LLMRetryPolicy()
        policy.connect = LLMRetryRule(attempts: 4, intervalMs: 1000)
        policy.empty = LLMRetryRule(attempts: -1, intervalMs: 0)
        policy.stream = LLMRetryRule(attempts: 2, intervalMs: 500)
        policy.breaker = LLMRetryRule(attempts: 3, intervalMs: 60_000)
        policy.intent = LLMRetryRule(attempts: 1, intervalMs: 3000)
        guard try await service.saveRetry(policy) == policy, try await service.retry() == policy else { throw RuntimeError.integrity("retry policy roundtrip") }
        try await service.delete(id: String(other), isActive: false)
        try await service.delete(id: String(excluded), isActive: false)
        let remaining = try await service.profiles()
        guard remaining.count == 1, let active = remaining.first, active.isDefault else { throw RuntimeError.integrity("inactive deletion and active profile") }
        let profile = try normalized(active)
        let snapshot = Snapshot(activeID: active.id, profile: profile, policy: policy)
        let contract: [String: Any] = ["profile": profile, "retry_policy": try JSONSerialization.jsonObject(with: LLMWire.encode(policy)),
                                     "rotation_enabled": chain.enabled, "bind_fallback": chain.bindFallback,
                                     "created_formats": created.map { $0.format.rawValue }.sorted(), "active_delete_status": protectedDelete.status,
                                     "inactive_delete_remaining": remaining.count, "blank_key_preserved": true,
                                     "missing_key_models_rejected": true, "missing_key_test_rejected": true]
        try JSONSerialization.data(withJSONObject: contract, options: [.prettyPrinted, .sortedKeys]).write(to: directory.appendingPathComponent("llm-contract-vm.json"))
        return snapshot
    }
    static func verify(_ snapshot: Snapshot, session: AuthenticationSession) async throws {
        let service = LLMService(client: AuthenticatedBackendClient(session: session))
        let profiles = try await service.profiles()
        guard let active = profiles.first(where: { $0.id == snapshot.activeID }), active.isDefault,
              try JSONSerialization.data(withJSONObject: normalized(active), options: [.sortedKeys]) == JSONSerialization.data(withJSONObject: snapshot.profile, options: [.sortedKeys]),
              try await service.retry() == snapshot.policy else { throw RuntimeError.integrity("native LLM restart persistence") }
        let pool = try await service.pool()
        guard pool.enabled, pool.bindFallback else { throw RuntimeError.integrity("rotation setting persistence") }
    }
    private static func normalized(_ p: LLMProfile) throws -> [String: Any] {
        ["name": p.name, "format": p.format.rawValue, "model": p.model, "is_default": p.isDefault, "base_url": p.baseUrl ?? "", "proxy": p.proxy ?? "",
         "key_present": p.apiKeyHint?.isEmpty == false, "rate_per_second": p.ratePerSecond, "rate_per_minute": p.ratePerMinute,
         "context_window_k": p.contextWindowK ?? 0, "thinking_type": p.thinkingType ?? "", "reasoning_effort": p.reasoningEffort ?? "",
         "priority": p.priority ?? 0, "pool_exclude": p.poolExclude ?? false, "streaming": p.streaming ?? true,
         "max_tokens": p.maxTokens ?? 0, "max_tokens_field": p.maxTokensField ?? "", "session_header_key": p.sessionHeaderKey ?? "",
         "retry": try JSONSerialization.jsonObject(with: LLMWire.encode(p.retry ?? LLMRetryOverride()))]
    }
}
#endif
