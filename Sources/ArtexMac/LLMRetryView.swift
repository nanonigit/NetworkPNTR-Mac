import ArtexCore
import SwiftUI

@MainActor struct LLMRetryView: View {
    let store: LLMStore
    @State private var policy = LLMRetryPolicy()
    @State private var dirty = false
    @State private var invalid: Set<String> = []
    @State private var confirmReload = false
    @State private var fieldGeneration = UUID()
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("全体の再試行ポリシー").font(.title2.bold())
            Text("接続 → 空応答 → ストリーム → ローテーションの遮断 → 意図の再実行の順に適用します。最初の3層はモデル設定ごとに上書きできます。")
                .font(.callout).foregroundStyle(.secondary)
            ScrollView {
                VStack(spacing: 14) {
                    fields("接続", "接続失敗・タイムアウト・408・429・500/502/503/504。HTTP 200を受け取る前に適用します。", \.connect, "connect")
                    fields("空応答", "OpenAI形式のみ。正常終了しても本文が空の応答を再試行します。", \.empty, "empty")
                    fields("ストリーム", "出力をまだ届けていない時の切断や一時障害。出力開始後の内容を二重に流しません。", \.stream, "stream")
                    fields("ローテーションの遮断", "連続する一時障害で接続先を一時的に除外します。無効設定や残高不足等の恒久エラーは即座に遮断されます。", \.breaker, "breaker")
                    fields("意図の再実行", "workerがmodel_errorで終了した場合に、意図全体を再試行します。", \.intent, "intent")
                }.id(fieldGeneration).padding(.bottom)
            }
            HStack {
                if dirty { Text("未保存の変更があります").font(.caption).foregroundStyle(.secondary) }
                Spacer()
                Button("再取得") { if dirty || !invalid.isEmpty { confirmReload = true } else { reload() } }
                Button("保存") {
                    let snapshot = policy
                    Task { if await store.saveRetry(snapshot) { policy = store.retryPolicy ?? snapshot.clamped(); dirty = false; fieldGeneration = UUID(); invalid = [] } }
                }.buttonStyle(.borderedProminent).disabled(!invalid.isEmpty || store.retryPolicy == nil)
            }.disabled(store.isLoading || store.isMutating)
        }
        .task { if let saved = store.retryPolicy { policy = saved } }
        .onChange(of: store.retryPolicy) { _, saved in if !dirty, invalid.isEmpty, let saved { policy = saved } }
        .confirmationDialog("未保存の変更を破棄して再取得しますか？", isPresented: $confirmReload, titleVisibility: .visible) {
            Button("再取得", role: .destructive, action: reload)
            Button("キャンセル", role: .cancel) {}
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
