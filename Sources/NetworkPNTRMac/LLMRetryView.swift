import NetworkPNTRCore
import SwiftUI

@MainActor struct LLMRetryView: View {
    @Environment(\.locale) private var locale
    private var language: AppLanguage { AppLanguage.preferred(in: [locale.identifier]) }
    private func s(_ key: AppStringKey) -> String { AppStrings.text(key, language: language) }
    let store: LLMStore
    @State private var policy = LLMRetryPolicy()
    @State private var dirty = false
    @State private var invalid: Set<String> = []
    @State private var confirmReload = false
    @State private var fieldGeneration = UUID()
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(s(.llmUIGlobalRetry)).font(.title2.bold())
            Text(s(.llmUIRetryHelp))
                .font(.callout).foregroundStyle(.secondary)
            ScrollView {
                VStack(spacing: 14) {
                    fields(s(.llmUIConnection), s(.llmUIGlobalConnectDetail), \.connect, "connect")
                    fields(s(.llmUIEmpty), s(.llmUIGlobalEmptyDetail), \.empty, "empty")
                    fields(s(.llmUIStream), s(.llmUIGlobalStreamDetail), \.stream, "stream")
                    fields(s(.llmUIBreaker), s(.llmUIBreakerHelp), \.breaker, "breaker")
                    fields(s(.llmUIIntent), s(.llmUIIntentHelp), \.intent, "intent")
                }.id(fieldGeneration).padding(.bottom)
            }
            HStack {
                if dirty { Text(s(.llmUIUnsaved)).font(.caption).foregroundStyle(.secondary) }
                Spacer()
                Button(s(.llmUIRefetch)) { if dirty || !invalid.isEmpty { confirmReload = true } else { reload() } }
                Button(s(.llmUISave)) {
                    let snapshot = policy
                    Task { if await store.saveRetry(snapshot) { policy = store.retryPolicy ?? snapshot.clamped(); dirty = false; fieldGeneration = UUID(); invalid = [] } }
                }.buttonStyle(.borderedProminent).disabled(!invalid.isEmpty || store.retryPolicy == nil || store.unknownRevision != nil)
            }.disabled(store.isLoading || store.isMutating)
        }
        .task { if let saved = store.retryPolicy { policy = saved } }
        .onChange(of: store.retryPolicy) { _, saved in if !dirty, invalid.isEmpty, let saved { policy = saved } }
        .confirmationDialog(s(.llmUIDiscardConfirm), isPresented: $confirmReload, titleVisibility: .visible) {
            Button(s(.llmUIRefetch), role: .destructive, action: reload)
            Button(s(.llmUICancel), role: .cancel) {}
        }
    }
    private func reload() {
        Task {
            await store.load()
            if store.error == nil, let saved = store.retryPolicy { policy = saved; dirty = false; invalid = []; fieldGeneration = UUID() }
        }
    }
    private func fields(_ title: String, _ detail: String, _ key: WritableKeyPath<LLMRetryPolicy, LLMRetryRule>, _ prefix: String) -> some View {
        LLMRetryRuleFields(title: title, detail: detail, rule: Binding(get: { policy[keyPath: key] }, set: { policy[keyPath: key] = $0; dirty = true })) { field, valid in
            if valid { invalid.remove(prefix + field) } else { invalid.insert(prefix + field) }
        }.disabled(store.isLoading || store.isMutating)
    }
}
