import ArtexCore
import SwiftUI

@MainActor struct LLMProfileEditor: View {
    @Environment(\.locale) private var locale
    private var language: AppLanguage { AppLanguage.preferred(in: [locale.identifier]) }
    private func s(_ key: AppStringKey) -> String { AppStrings.text(key, language: language) }
    private func f(_ key: AppStringKey, _ values: [String: String]) -> String { AppStrings.formatted(key, language: language, values: values) }
    let store: LLMStore
    let context: LLMEditorContext
    @Environment(\.dismiss) private var dismiss
    @State private var draft: LLMProfileDraft
    @State private var numberErrors: Set<String> = []
    @State private var error: AppErrorMessage?
    @State private var testing = false
    @State private var loadingModels = false
    @State private var models: [String] = []
    @State private var modelsOpen = false
    @State private var testResult: LLMConnectionResult?
    init(store: LLMStore, context: LLMEditorContext) {
        self.store = store; self.context = context
        _draft = State(initialValue: context.draft)
    }
    private var busy: Bool { testing || loadingModels || store.isLoading || store.isMutating }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text(draft.id == nil ? s(.llmUICreateTitle) : s(.llmUIEditTitle)).font(.title2.bold())
                Text(s(.llmUIActivateHint)).font(.caption).foregroundStyle(.secondary)
            }.padding(24)
            Form {
                Section(s(.llmUIConnection)) {
                    TextField(s(.llmUIName), text: $draft.name)
                    Picker(s(.llmUIFormat), selection: $draft.format) {
                        Text("Anthropic").tag(LLMFormat.anthropic)
                        Text("OpenAI Chat Completions").tag(LLMFormat.openai)
                        Text("OpenAI Responses").tag(LLMFormat.openaiResponses)
                    }
                    TextField(s(.llmUIModel), text: $draft.model)
                    HStack {
                        Button(s(.llmUIFetchModels)) { fetchModels() }
                        if !models.isEmpty {
                            Button(f(.llmUIModelCandidates, ["count": String(models.count)])) { modelsOpen = true }
                                .popover(isPresented: $modelsOpen) {
                                    LLMModelPicker(models: models) { draft.model = $0; modelsOpen = false }
                                }
                        }
                        if loadingModels { ProgressView().controlSize(.small) }
                    }
                    TextField(s(.llmUIBaseURL), text: $draft.baseUrl)
                    TextField(s(.llmUIProxy), text: $draft.proxy)
                    Text(s(.llmUIProxyHelp))
                        .font(.caption).foregroundStyle(.secondary)
                    TextField(s(.llmUISessionHeader), text: $draft.sessionHeaderKey)
                    Text(s(.llmUISessionHelp))
                        .font(.caption).foregroundStyle(.secondary)
                    SecureField(s(.llmUIAPIKey), text: $draft.apiKey)
                    if !context.keyHint.isEmpty { Text(f(.llmUISavedKeyHint, ["hint": context.keyHint])).font(.caption).foregroundStyle(.secondary) }
                }
                Section(s(.llmUILimits)) {
                    LLMNumberField(s(.llmUIPerSecond), value: $draft.ratePerSecond, valid: { $0.isFinite && $0 >= 0 }) { mark("rps", $0) }
                    LLMNumberField(s(.llmUIPerMinute), value: $draft.ratePerMinute, valid: { $0.isFinite && $0 >= 0 }) { mark("rpm", $0) }
                    LLMNumberField(s(.llmUIContext), value: $draft.contextWindowK, valid: { (0...1000).contains($0) }) { mark("context", $0) }
                    Text(s(.llmUILimitsHelp)).font(.caption).foregroundStyle(.secondary)
                    LLMNumberField(s(.llmUIPriority), value: $draft.priority, valid: { _ in true }) { mark("priority", $0) }
                    Text(s(.llmUIPriorityHelp)).font(.caption).foregroundStyle(.secondary)
                    Toggle(s(.llmUIExcludeRotation), isOn: $draft.poolExclude)
                    Text(s(.llmUIExcludeHelp)).font(.caption).foregroundStyle(.secondary)
                    Toggle(s(.llmUIStreaming), isOn: $draft.streaming)
                    Text(s(.llmUIStreamingHelp)).font(.caption).foregroundStyle(.secondary)
                    LLMNumberField(s(.llmUIMaxTokens), value: $draft.maxTokens, valid: { $0 >= 0 }) { mark("tokens", $0) }
                    Text(s(.llmUIMaxTokensHelp)).font(.caption).foregroundStyle(.secondary)
                    Picker(s(.llmUIMaxTokensField), selection: $draft.maxTokensField) {
                        Text(s(.llmUIDefaultMaxTokens)).tag("")
                        Text("max_completion_tokens").tag("max_completion_tokens")
                    }.disabled(draft.format != .openai)
                }
                Section(s(.llmUIThinking)) {
                    Picker(s(.llmUIThinkingSwitch), selection: $draft.thinkingType) {
                        Text(s(.llmUIOmit)).tag(""); Text(s(.llmUIDisabled)).tag("disabled"); Text(s(.llmUIEnabled)).tag("enabled")
                    }
                    Picker(s(.llmUIEffort), selection: $draft.reasoningEffort) {
                        Text(s(.llmUIOmit)).tag("")
                        ForEach(["low", "medium", "high", "xhigh", "max"], id: \.self) { Text($0).tag($0) }
                    }
                    Text(s(.llmUIThinkingHelp)).font(.caption).foregroundStyle(.secondary)
                }
                Section(s(.llmUIProfileRetry)) {
                    LLMRetryRuleFields(title: s(.llmUIConnection), detail: s(.llmUIConnectDetail), rule: $draft.retry.connect) { mark("connect." + $0, $1) }
                    LLMRetryRuleFields(title: s(.llmUIEmpty), detail: s(.llmUIEmptyDetail), rule: $draft.retry.empty) { mark("empty." + $0, $1) }
                    LLMRetryRuleFields(title: s(.llmUIStream), detail: s(.llmUIStreamDetail), rule: $draft.retry.stream) { mark("stream." + $0, $1) }
                }
            }.formStyle(.grouped).disabled(busy)
            VStack(alignment: .leading, spacing: 10) {
                LLMRecoveryView(store: store)
                if let error { Text(error.text(language: language)).foregroundStyle(.red).textSelection(.enabled) }
                if let result = testResult {
                    Text(f(.llmUITestSuccess, ["model": result.model ?? draft.model, "latency": (result.latencyMs ?? 0).formatted(.number.precision(.fractionLength(0)))])).foregroundStyle(.green)
                    if let reply = result.reply { Text(reply).font(.caption).lineLimit(5).textSelection(.enabled) }
                }
                HStack {
                    Button(s(.llmUIClose)) { dismiss() }.keyboardShortcut(.cancelAction).disabled(store.isMutating)
                    Spacer()
                    if busy { ProgressView().controlSize(.small) }
                    Button(s(.llmUITest)) { test() }.disabled(busy || !numberErrors.isEmpty)
                    Button(s(.llmUISave)) { save() }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                        .disabled(busy || store.unknownRevision != nil || !numberErrors.isEmpty || draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || draft.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
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
            catch { self.error = AppErrorMessage(error) }
        }
    }
    private func test() {
        guard !busy else { return }
        let snapshot = draft
        testing = true; error = nil; testResult = nil
        Task {
            defer { testing = false }
            do { testResult = try await store.service.test(snapshot) }
            catch { self.error = AppErrorMessage(error) }
        }
    }
    private func save() {
        guard !busy, numberErrors.isEmpty else { return }
        let snapshot = draft
        error = nil
        Task { if await store.save(snapshot) { draft.apiKey = ""; dismiss() } else { error = store.failure } }
    }
}

private struct LLMModelPicker: View {
    @Environment(\.locale) private var locale
    private var language: AppLanguage { AppLanguage.preferred(in: [locale.identifier]) }
    private func s(_ key: AppStringKey) -> String { AppStrings.text(key, language: language) }
    let models: [String]
    let select: (String) -> Void
    @State private var search = ""
    private var filtered: [String] { search.isEmpty ? models : models.filter { $0.localizedCaseInsensitiveContains(search) } }
    var body: some View {
        VStack(alignment: .leading) {
            TextField(s(.llmUISearchModels), text: $search).textFieldStyle(.roundedBorder)
            List(Array(filtered.enumerated()), id: \.offset) { _, model in Button(model) { select(model) }.buttonStyle(.plain) }
            if filtered.isEmpty { Text(s(.llmUINoMatchingModels)).foregroundStyle(.secondary) }
        }.padding(14).frame(width: 400, height: 340)
    }
}
