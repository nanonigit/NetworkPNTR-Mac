import NetworkPNTRCore
import SwiftUI

/// Recovery never repeats a write. The store requires an owned full reload and explicit revision acknowledgement.
@MainActor struct LLMRecoveryView: View {
    @Environment(\.locale) private var locale
    let store: LLMStore
    @State private var overviewExpanded = true
    private func s(_ key: AppStringKey) -> String {
        AppStrings.text(key, language: AppLanguage.preferred(in: [locale.identifier]))
    }
    var body: some View {
        if let revision = store.unknownRevision {
            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    Label(s(.llmUIRecoveryTitle), systemImage: "exclamationmark.triangle").font(.headline)
                    Text(s(.llmUIRecoveryHelp)).font(.callout).fixedSize(horizontal: false, vertical: true)
                    if store.canAcknowledgeUnknown {
                        DisclosureGroup(s(.llmUIRecoveryOverview), isExpanded: $overviewExpanded) {
                            ScrollView {
                                VStack(alignment: .leading, spacing: 8) {
                                    if store.profiles.isEmpty { Text(s(.llmUINoProfiles)) }
                                    ForEach(store.profiles) { profile in
                                        HStack(alignment: .top) {
                                            if profile.isDefault { Label(s(.llmUIActive), systemImage: "star.fill") }
                                            Text(profile.name); Text(profile.model).foregroundStyle(.secondary)
                                        }
                                    }
                                    if let pool = store.pool {
                                        Toggle(s(.llmUIEnableRotation), isOn: .constant(pool.enabled)).disabled(true)
                                        Toggle(s(.llmUIAllowFallback), isOn: .constant(pool.bindFallback)).disabled(true)
                                    }
                                    if let policy = store.retryPolicy {
                                        Text(s(.llmUIGlobalRetry)).font(.headline)
                                        Text(s(.llmUIAttempts) + " / " + s(.llmUIInterval))
                                        rule(.llmUIConnection, policy.connect)
                                        rule(.llmUIEmpty, policy.empty)
                                        rule(.llmUIStream, policy.stream)
                                        rule(.llmUIBreaker, policy.breaker)
                                        rule(.llmUIIntent, policy.intent)
                                    }
                                }.font(.caption).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                            }.frame(maxHeight: 160)
                        }
                    }
                    Button(s(.llmUIReload)) { Task { await store.load() } }
                        .disabled(store.isLoading || store.isMutating || !store.isActive)
                    Button(s(.llmUIRecoveryResume)) { store.acknowledgeUnknown(revision: revision) }
                        .disabled(!store.canAcknowledgeUnknown)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
    private func rule(_ key: AppStringKey, _ rule: LLMRetryRule) -> some View {
        LabeledContent(s(key)) { Text("\(rule.attempts) / \(rule.intervalMs) ms") }
    }
}
