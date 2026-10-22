import ArtexCore
import SwiftUI

@MainActor struct LLMProfileEditor: View {
    let store: LLMStore
    let context: LLMEditorContext
    @Environment(\.dismiss) private var dismiss
    @State private var draft: LLMProfileDraft
    @State private var numberErrors: Set<String> = []
    @State private var error: String?
    @State private var testing = false
    @State private var loadingModels = false
    @State private var models: [String] = []
    @State private var modelsOpen = false
    @State private var testResult: LLMConnectionResult?
    init(store: LLMStore, context: LLMEditorContext) {
        self.store = store; self.context = context
        _draft = State(initialValue: context.draft)
    }
    private var busy: Bool { testing || loadingModels || store.isMutating }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text(draft.id == nil ? "モデル設定を作成" : "モデル設定を編集").font(.title2.bold())
                Text("新規作成だけでは有効になりません。一覧で「有効にする」を選びます。").font(.caption).foregroundStyle(.secondary)
            }.padding(24)
            Form {
                Section("接続") {
                    TextField("名前", text: $draft.name)
                    Picker("API形式", selection: $draft.format) {
                        Text("Anthropic").tag(LLMFormat.anthropic)
                        Text("OpenAI Chat Completions").tag(LLMFormat.openai)
                        Text("OpenAI Responses").tag(LLMFormat.openaiResponses)
                    }
                    TextField("モデル", text: $draft.model)
                    HStack {
                        Button("モデル一覧を取得") { fetchModels() }
                        if !models.isEmpty {
                            Button("モデル候補（\(models.count)）") { modelsOpen = true }
                                .popover(isPresented: $modelsOpen) {
                                    LLMModelPicker(models: models) { draft.model = $0; modelsOpen = false }
                                }
                        }
                        if loadingModels { ProgressView().controlSize(.small) }
                    }
                    TextField("Base URL（省略可）", text: $draft.baseUrl)
                    TextField("プロキシ（省略可）", text: $draft.proxy)
                    Text("プロキシはLLMの外向き通信に適用します。HTTP/HTTPS/SOCKS5を指定でき、空欄は直接接続です。現在の専用VMは外向き通信の検証待ちです。")
                        .font(.caption).foregroundStyle(.secondary)
                    TextField("セッションヘッダー名（省略可）", text: $draft.sessionHeaderKey)
                    Text("指定すると、同じ会話・タスクのセッションIDをこのヘッダーで送信します。空欄では送りません。")
                        .font(.caption).foregroundStyle(.secondary)
                    SecureField("APIキー", text: $draft.apiKey)
                    if !context.keyHint.isEmpty { Text("保存済み：\(context.keyHint) · 空欄のまま保存すると既存のキーを保持します。").font(.caption).foregroundStyle(.secondary) }
                }
                Section("制限") {
                    LLMNumberField("秒あたりの回数", value: $draft.ratePerSecond, valid: { $0.isFinite && $0 >= 0 }) { mark("rps", $0) }
                    LLMNumberField("分あたりの回数", value: $draft.ratePerMinute, valid: { $0.isFinite && $0 >= 0 }) { mark("rpm", $0) }
                    LLMNumberField("コンテキスト（K）", value: $draft.contextWindowK, valid: { (0...1000).contains($0) }) { mark("context", $0) }
                    Text("回数0は無制限で全エージェントが共有します。コンテキスト0は既定の200K、上限は1000Kです。").font(.caption).foregroundStyle(.secondary)
                    LLMNumberField("優先順位", value: $draft.priority, valid: { _ in true }) { mark("priority", $0) }
                    Text("大きい値から優先します。有効な設定は常に先頭、同順位は交代して使います。").font(.caption).foregroundStyle(.secondary)
                    Toggle("ローテーションの対象から除外", isOn: $draft.poolExclude)
                    Text("除外してもエージェントやタスクから個別指定できます。").font(.caption).foregroundStyle(.secondary)
                    Toggle("ストリーミング出力", isOn: $draft.streaming)
                    Text("オフでは応答全体をまとめて受信します。ゲートウェイのSSEに問題がある場合に使えます。").font(.caption).foregroundStyle(.secondary)
                    LLMNumberField("1回の応答の出力上限", value: $draft.maxTokens, valid: { $0 >= 0 }) { mark("tokens", $0) }
                    Text("0では上限フィールドを送らず、接続先の既定値を使います。コンテキスト全体の容量とは別の設定です。").font(.caption).foregroundStyle(.secondary)
                    Picker("出力上限のフィールド名", selection: $draft.maxTokensField) {
                        Text("max_tokens（既定）").tag("")
                        Text("max_completion_tokens").tag("max_completion_tokens")
                    }.disabled(draft.format != .openai)
                }
                Section("思考") {
                    Picker("思考スイッチ", selection: $draft.thinkingType) {
                        Text("送信しない").tag(""); Text("無効（disabled）").tag("disabled"); Text("有効（enabled）").tag("enabled")
                    }
                    Picker("思考強度", selection: $draft.reasoningEffort) {
                        Text("送信しない").tag("")
                        ForEach(["low", "medium", "high", "xhigh", "max"], id: \.self) { Text($0).tag($0) }
                    }
                    Text("思考スイッチと思考強度は独立したパラメーターです。対応していないモデルでは送信しない設定を選びます。").font(.caption).foregroundStyle(.secondary)
                }
                Section("この設定だけの再試行") {
                    LLMRetryRuleFields(title: "接続", detail: "接続確立前のネットワーク障害や408・429・5xx", rule: $draft.retry.connect) { mark("connect." + $0, $1) }
                    LLMRetryRuleFields(title: "空応答", detail: "OpenAI形式で正常終了したのに本文が空の場合", rule: $draft.retry.empty) { mark("empty." + $0, $1) }
                    LLMRetryRuleFields(title: "ストリーム", detail: "まだ1トークンも受け取っていない時の切断や一時障害", rule: $draft.retry.stream) { mark("stream." + $0, $1) }
                }
            }.formStyle(.grouped).disabled(busy)
            VStack(alignment: .leading, spacing: 10) {
                if let error { Text(error).foregroundStyle(.red).textSelection(.enabled) }
                if let result = testResult {
                    Text("接続成功 · \(result.model ?? draft.model) · \((result.latencyMs ?? 0).formatted(.number.precision(.fractionLength(0))))ms").foregroundStyle(.green)
                    if let reply = result.reply { Text(reply).font(.caption).lineLimit(5).textSelection(.enabled) }
                }
                HStack {
                    Button("閉じる") { dismiss() }.keyboardShortcut(.cancelAction).disabled(store.isMutating)
                    Spacer()
                    if busy { ProgressView().controlSize(.small) }
                    Button("接続テスト") { test() }.disabled(busy || !numberErrors.isEmpty)
                    Button("保存") { save() }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                        .disabled(busy || !numberErrors.isEmpty || draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || draft.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }.padding(20)
        }
        .frame(width: 680, height: 780)
        .onChange(of: draft.format) { _, _ in models = []; testResult = nil; if draft.format != .openai { draft.maxTokensField = "" } }
        .onChange(of: draft) { _, _ in testResult = nil }
        .onDisappear { draft.apiKey = ""; draft.proxy = "" }
    }
    private func mark(_ field: String, _ valid: Bool) { if valid { numberErrors.remove(field) } else { numberErrors.insert(field) } }
    private func fetchModels() {
        guard !busy else { return }
        let snapshot = draft
        loadingModels = true; error = nil; models = []
        Task {
            defer { loadingModels = false }
            do { models = try await store.service.models(snapshot); modelsOpen = true }
            catch { self.error = error.localizedDescription }
        }
    }
    private func test() {
        guard !busy else { return }
        let snapshot = draft
        testing = true; error = nil; testResult = nil
        Task {
            defer { testing = false }
            do { testResult = try await store.service.test(snapshot) }
            catch { self.error = error.localizedDescription }
        }
    }
    private func save() {
        guard !busy, numberErrors.isEmpty else { return }
        let snapshot = draft
        error = nil
        Task { if await store.save(snapshot) { draft.apiKey = ""; dismiss() } else { error = store.error } }
    }
}

private struct LLMModelPicker: View {
    let models: [String]
    let select: (String) -> Void
    @State private var search = ""
    private var filtered: [String] { search.isEmpty ? models : models.filter { $0.localizedCaseInsensitiveContains(search) } }
    var body: some View {
        VStack(alignment: .leading) {
            TextField("モデルを検索", text: $search).textFieldStyle(.roundedBorder)
            List(Array(filtered.enumerated()), id: \.offset) { _, model in Button(model) { select(model) }.buttonStyle(.plain) }
            if filtered.isEmpty { Text("一致するモデルがありません").foregroundStyle(.secondary) }
        }.padding(14).frame(width: 400, height: 340)
    }
}
