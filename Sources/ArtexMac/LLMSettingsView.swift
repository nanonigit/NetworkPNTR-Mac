import ArtexCore
import SwiftUI

@MainActor struct LLMSettingsView: View {
    @State private var store: LLMStore
    @State private var editor: LLMEditorContext?
    @State private var rotationOpen = false
    @State private var selectedTab = 0
    @State private var deleteCandidate: LLMProfile?
    @State private var localError: String?
    init(session: AuthenticationSession) {
        _store = State(initialValue: LLMStore(service: LLMService(client: AuthenticatedBackendClient(session: session))))
    }
    private var busy: Bool { store.isLoading || store.isMutating }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("LLM").font(.largeTitle.bold())
                    Text("全エージェントで使うモデル・API形式・制限を管理します。有効な設定には星が付きます。")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("ローテーション", systemImage: "bolt") { rotationOpen = true }
                Button("新規", systemImage: "plus") { editor = LLMEditorContext(draft: LLMProfileDraft(), keyHint: "") }
                Button { Task { await store.load() } } label: { Image(systemName: "arrow.clockwise") }.help("再読み込み")
            }.disabled(busy)
            if let error = localError ?? store.error {
                Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red).textSelection(.enabled)
                if store.hasLoaded { Text("前回取得した内容を表示しています。再読み込みしてください。").font(.caption).foregroundStyle(.secondary) }
            }
            if let notice = store.notice { Text(notice).font(.callout).foregroundStyle(.green) }
            if busy { ProgressView(store.isMutating ? "変更を保存しています" : "設定を読み込んでいます").controlSize(.small) }
            Picker("表示", selection: $selectedTab) {
                Text("モデル設定").tag(0)
                Text("再試行と待機").tag(1)
            }.pickerStyle(.segmented).frame(maxWidth: 360)
            if selectedTab == 0 {
                ScrollView {
                    if store.hasLoaded && store.profiles.isEmpty {
                        ContentUnavailableView("モデル設定がありません", systemImage: "brain", description: Text("新規設定を作成し、使う設定を有効にしてください。"))
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
        .task { await store.load() }
        .sheet(item: $editor) { context in LLMProfileEditor(store: store, context: context) }
        .sheet(isPresented: $rotationOpen) { LLMRotationView(store: store) }
        .confirmationDialog("このモデル設定を削除しますか？", isPresented: Binding(get: { deleteCandidate != nil }, set: { if !$0 { deleteCandidate = nil } }), titleVisibility: .visible) {
            if let candidate = deleteCandidate {
                Button("削除", role: .destructive) { Task { await store.delete(candidate); deleteCandidate = nil } }
            }
            Button("キャンセル", role: .cancel) { deleteCandidate = nil }
        } message: { Text("この設定を参照するタスク等は、ブラウザ版と同じバックエンド処理で更新されます。") }
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
                Text(profile.apiKeyHint?.isEmpty == false ? (member?.state == "tripped" ? "待機中：\(member?.cooldownSecs ?? 0)秒" : member?.state == "degraded" ? "連続失敗：\(member?.fails ?? 0)" : "正常") : "APIキー未設定")
                    .font(.caption).foregroundStyle(profile.apiKeyHint?.isEmpty == false ? Color.secondary : Color.orange)
                if let hint = profile.apiKeyHint, !hint.isEmpty { Text(hint).font(.caption).foregroundStyle(.secondary) }
                Text("\(profile.ratePerSecond.formatted())/秒 · \(profile.ratePerMinute.formatted())/分").font(.caption).foregroundStyle(.secondary)
                if profile.proxy?.isEmpty == false { Text("プロキシ設定あり").font(.caption).foregroundStyle(.secondary) }
                if let effort = profile.reasoningEffort, !effort.isEmpty { Text("思考強度：\(effort)").font(.caption) }
                if store.pool?.enabled == true && !profile.isDefault { Text(profile.poolExclude == true ? "ローテーション対象外" : "優先順位：\(profile.priority ?? 0)").font(.caption) }
                HStack {
                    Button("編集") {
                        do { editor = LLMEditorContext(draft: try LLMProfileDraft(profile: profile), keyHint: profile.apiKeyHint ?? ""); localError = nil }
                        catch { localError = error.localizedDescription }
                    }
                    Button(profile.isDefault ? "有効" : "有効にする") { Task { await store.activate(profile) } }.disabled(profile.isDefault)
                    Spacer()
                    Button(role: .destructive) { deleteCandidate = profile } label: { Image(systemName: "trash") }.disabled(profile.isDefault).help("モデル設定を削除")
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
