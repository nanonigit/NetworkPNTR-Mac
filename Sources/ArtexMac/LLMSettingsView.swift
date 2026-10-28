import ArtexCore
import SwiftUI

@MainActor struct LLMSettingsView: View {
    @Environment(\.locale) private var locale
    private var language: AppLanguage { AppLanguage.preferred(in: [locale.identifier]) }
    private func s(_ key: AppStringKey) -> String { AppStrings.text(key, language: language) }
    private func f(_ key: AppStringKey, _ values: [String: String]) -> String { AppStrings.formatted(key, language: language, values: values) }
    @State private var store: LLMStore
    @State private var editor: LLMEditorContext?
    @State private var rotationOpen = false
    @State private var selectedTab = 0
    @State private var deleteCandidate: LLMProfile?
    @State private var localError: AppErrorMessage?
    init(session: AuthenticationSession) {
        _store = State(initialValue: LLMStore(service: LLMService(client: AuthenticatedBackendClient(session: session))))
    }
    private var busy: Bool { store.isLoading || store.isMutating }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("LLM").font(.largeTitle.bold())
                    Text(s(.llmUIDescription))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(s(.llmUIRotation), systemImage: "bolt") { rotationOpen = true }
                Button(s(.llmUINew), systemImage: "plus") { editor = LLMEditorContext(draft: LLMProfileDraft(), keyHint: "") }
                Button { Task { await store.load() } } label: { Image(systemName: "arrow.clockwise") }.help(s(.llmUIReload))
            }.disabled(busy)
            if let error = (localError ?? store.failure)?.text(language: language) {
                Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red).textSelection(.enabled)
                if store.hasLoaded { Text(s(.llmUIStale)).font(.caption).foregroundStyle(.secondary) }
            }
            LLMRecoveryView(store: store)
            if let key = store.noticeKey { Text(AppStrings.text(key, language: language)).font(.callout).foregroundStyle(.green) }
            if busy { ProgressView(store.isMutating ? s(.llmUISaving) : s(.llmUILoading)).controlSize(.small) }
            Picker(s(.llmUIDisplay), selection: $selectedTab) {
                Text(s(.llmUIProfiles)).tag(0)
                Text(s(.llmUIRetryTab)).tag(1)
            }.pickerStyle(.segmented).frame(maxWidth: 360)
            if selectedTab == 0 {
                ScrollView {
                    if store.hasLoaded && store.profiles.isEmpty {
                        ContentUnavailableView(s(.llmUINoProfiles), systemImage: "brain", description: Text(s(.llmUICreateHint)))
                    } else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), alignment: .top)], spacing: 16) {
                            ForEach(store.profiles) { profile in profileCard(profile) }
                        }.padding(.bottom)
                    }
                }
            } else { LLMRetryView(store: store) }
        }
        .padding(28)
        .background(Color(nsColor: .windowBackgroundColor))
        .navigationTitle("LLM")
        .task { store.resume(); await store.load() }
        .onDisappear { store.stop() }
        .sheet(item: $editor) { context in LLMProfileEditor(store: store, context: context) }
        .sheet(isPresented: $rotationOpen) { LLMRotationView(store: store) }
        .confirmationDialog(s(.llmUIDeleteConfirm), isPresented: Binding(get: { deleteCandidate != nil }, set: { if !$0 { deleteCandidate = nil } }), titleVisibility: .visible) {
            if let candidate = deleteCandidate {
                Button(s(.llmUIDelete), role: .destructive) { Task { await store.delete(candidate); deleteCandidate = nil } }
            }
            Button(s(.llmUICancel), role: .cancel) { deleteCandidate = nil }
        } message: { Text(s(.llmUIDeleteHelp)) }
    }
    private func profileCard(_ profile: LLMProfile) -> some View {
        let member = store.pool?.chain.first(where: { $0.profileId == profile.id })
        return GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: profile.isDefault ? "star.fill" : "star").foregroundStyle(profile.isDefault ? .yellow : .secondary)
                    Text(profile.name).font(.headline)
                    Spacer()
                    Text(profile.format.rawValue).font(.caption).foregroundStyle(.secondary)
                }
                Text(profile.model).font(.system(.callout, design: .monospaced)).textSelection(.enabled)
                Text(profile.apiKeyHint?.isEmpty == false ? (member?.state == "tripped" ? f(.llmUICooldown, ["seconds": String(member?.cooldownSecs ?? 0)]) : member?.state == "degraded" ? f(.llmUIFailures, ["count": String(member?.fails ?? 0)]) : s(.llmUIHealthy)) : s(.llmUINoKey))
                    .font(.caption).foregroundStyle(profile.apiKeyHint?.isEmpty == false ? Color.secondary : Color.orange)
                if let hint = profile.apiKeyHint, !hint.isEmpty { Text(hint).font(.caption).foregroundStyle(.secondary) }
                Text(f(.llmUIRates, ["second": profile.ratePerSecond.formatted(), "minute": profile.ratePerMinute.formatted()])).font(.caption).foregroundStyle(.secondary)
                if profile.proxy?.isEmpty == false { Text(s(.llmUIProxySet)).font(.caption).foregroundStyle(.secondary) }
                if let effort = profile.reasoningEffort, !effort.isEmpty { Text(f(.llmUIEffortValue, ["value": effort])).font(.caption) }
                if store.pool?.enabled == true && !profile.isDefault { Text(profile.poolExclude == true ? s(.llmUIExcluded) : f(.llmUIPriorityValue, ["value": String(profile.priority ?? 0)])).font(.caption) }
                HStack {
                    Button(s(.llmUIEdit)) {
                        do { editor = LLMEditorContext(draft: try LLMProfileDraft(profile: profile), keyHint: profile.apiKeyHint ?? ""); localError = nil }
                        catch { localError = AppErrorMessage(error) }
                    }
                    Button(profile.isDefault ? s(.llmUIActive) : s(.llmUIActivate)) { Task { await store.activate(profile) } }.disabled(profile.isDefault || store.unknownRevision != nil)
                    Spacer()
                    Button(role: .destructive) { deleteCandidate = profile } label: { Image(systemName: "trash") }.disabled(profile.isDefault || store.unknownRevision != nil).help(s(.llmUIDeleteProfile))
                }.disabled(busy)
            }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
        }
    }
}
struct LLMEditorContext: Identifiable {
    let id = UUID()
    let draft: LLMProfileDraft
    let keyHint: String
}
