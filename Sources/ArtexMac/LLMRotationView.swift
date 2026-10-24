import ArtexCore
import SwiftUI

@MainActor struct LLMRotationView: View {
    @Environment(\.locale) private var locale
    private var language: AppLanguage { AppLanguage.preferred(in: [locale.identifier]) }
    private func s(_ key: AppStringKey) -> String { AppStrings.text(key, language: language) }
    private func f(_ key: AppStringKey, _ values: [String: String]) -> String { AppStrings.formatted(key, language: language, values: values) }
    let store: LLMStore
    @Environment(\.dismiss) private var dismiss
    private var busy: Bool { store.isLoading || store.isMutating }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(s(.llmUIRotationTitle)).font(.title2.bold())
            Text(s(.llmUIRotationHelp))
                .foregroundStyle(.secondary)
            if store.pool == nil { ProgressView(s(.llmUIFetching)) }
            Toggle(s(.llmUIEnableRotation), isOn: Binding(get: { store.pool?.enabled ?? false }, set: { enabled in Task { await store.setRotation(enabled: enabled) } }))
                .disabled(busy || store.pool == nil)
            if let pool = store.pool, pool.enabled {
                Toggle(s(.llmUIAllowFallback), isOn: Binding(get: { store.pool?.bindFallback ?? false }, set: { fallback in Task { await store.setRotation(bindFallback: fallback) } })).disabled(busy)
                Text(s(.llmUIFallbackHelp)).font(.caption).foregroundStyle(.secondary)
                HStack {
                    Text(s(.llmUIAttemptOrder)).font(.headline)
                    Spacer()
                    Button(s(.llmUIResetAll)) { Task { await store.resetPool() } }.disabled(busy)
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(Array(pool.chain.enumerated()), id: \.element.id) { position, member in
                            GroupBox {
                                VStack(alignment: .leading, spacing: 7) {
                                    HStack {
                                        Text(member.excluded && !member.active ? s(.llmUINotEligible) : "\(pool.chain.prefix(position + 1).filter { $0.active || !$0.excluded }.count)")
                                        Text(member.name).font(.headline)
                                        if member.active { Text(s(.llmUIActive)).font(.caption).foregroundStyle(.orange) }
                                        Spacer()
                                        Text(member.state == "tripped" ? f(.llmUIRotationCooldown, ["seconds": String(member.cooldownSecs)]) : member.state == "degraded" ? f(.llmUIRotationFailures, ["count": String(member.fails)]) : s(.llmUIHealthy)).font(.caption)
                                    }
                                    Text(f(.llmUIModelPriority, ["model": member.model, "priority": String(member.priority)])).font(.caption).foregroundStyle(.secondary)
                                    if let error = member.lastError, !error.isEmpty { Text(error).font(.caption).textSelection(.enabled) }
                                    if member.state != "ok" { Button(s(.llmUIResetOne)) { Task { await store.resetPool(id: member.profileId) } }.disabled(busy) }
                                }.frame(maxWidth: .infinity, alignment: .leading).padding(6)
                            }
                        }
                        if pool.chain.isEmpty { ContentUnavailableView(s(.llmUINoProfiles), systemImage: "brain") }
                    }
                }
            } else { Spacer() }
            if let error = store.failure?.text(language: language) { Text(error).foregroundStyle(.red) }
            HStack { if busy { ProgressView().controlSize(.small) }; Spacer(); Button(s(.llmUIClose)) { dismiss() }.keyboardShortcut(.cancelAction) }
        }.padding(24).frame(width: 630, height: 680)
        .task {
            await store.refreshPool()
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(10)) } catch { return }
                if let pool = store.pool, pool.enabled, pool.chain.contains(where: { $0.state != "ok" }) { await store.refreshPool() }
            }
        }
    }
}
