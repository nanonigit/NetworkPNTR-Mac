import NetworkPNTRCore
import SwiftUI

@MainActor struct LLMProfileEditor: View {
    @Environment(\.locale) private var locale
    private var language: AppLanguage { AppLanguage.preferred(in: [locale.identifier]) }
    private func s(_ key: AppStringKey) -> String { AppStrings.text(key, language: language) }
    private func f(_ key: AppStringKey, _ values: [String: String]) -> String { AppStrings.formatted(key, language: language, values: values) }
    private var store: LLMStore { model.store }
    private let keyHint: String
    @Environment(\.dismiss) private var dismiss
    @State private var model: LLMEditorModel
    init(store: LLMStore, context: LLMEditorContext) {
        self.init(model: LLMEditorModel(store: store, draft: context.draft), keyHint: context.keyHint)
    }
    init(model: LLMEditorModel, keyHint: String) {
        self.keyHint = keyHint
        _model = State(initialValue: model)
    }
    private var busy: Bool { model.isBusy || store.isLoading || store.isMutating }
    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text(model.draft.id == nil ? s(.llmUICreateTitle) : s(.llmUIEditTitle)).font(.title2.bold())
                Text(s(.llmUIActivateHint)).font(.caption).foregroundStyle(.secondary)
            }.padding(24)
            Form {
                Section(s(.llmUIConnection)) {
                    TextField(s(.llmUIName), text: $model.draft.name)
                    Picker(s(.llmUIFormat), selection: $model.draft.format) {
                        Text("Anthropic").tag(LLMFormat.anthropic)
                        Text("OpenAI Chat Completions").tag(LLMFormat.openai)
                        Text("OpenAI Responses").tag(LLMFormat.openaiResponses)
                    }
                    TextField(s(.llmUIModel), text: $model.draft.model)
                    HStack {
                        Button(s(.llmUIFetchModels)) { model.fetchModels() }
                        if !model.models.isEmpty {
                            Button(f(.llmUIModelCandidates, ["count": String(model.models.count)])) { model.modelsOpen = true }
                                .popover(isPresented: $model.modelsOpen) {
                                    LLMModelPicker(models: model.models) { model.draft.model = $0; model.modelsOpen = false }
                                }
                        }
                        if model.loadingModels { ProgressView().controlSize(.small) }
                    }
                    TextField(s(.llmUIBaseURL), text: $model.draft.baseUrl)
                    TextField(s(.llmUIProxy), text: $model.draft.proxy)
                    Text(s(.llmUIProxyHelp))
                        .font(.caption).foregroundStyle(.secondary)
                    TextField(s(.llmUISessionHeader), text: $model.draft.sessionHeaderKey)
                    Text(s(.llmUISessionHelp))
                        .font(.caption).foregroundStyle(.secondary)
                    SecureField(s(.llmUIAPIKey), text: $model.draft.apiKey)
                    if !keyHint.isEmpty { Text(f(.llmUISavedKeyHint, ["hint": keyHint])).font(.caption).foregroundStyle(.secondary) }
                }
                Section(s(.llmUILimits)) {
                    LLMNumberField(s(.llmUIPerSecond), value: $model.draft.ratePerSecond, valid: { $0.isFinite && $0 >= 0 }) { mark("rps", $0) }
                    LLMNumberField(s(.llmUIPerMinute), value: $model.draft.ratePerMinute, valid: { $0.isFinite && $0 >= 0 }) { mark("rpm", $0) }
                    LLMNumberField(s(.llmUIContext), value: $model.draft.contextWindowK, valid: { (0...1000).contains($0) }) { mark("context", $0) }
                    Text(s(.llmUILimitsHelp)).font(.caption).foregroundStyle(.secondary)
                    LLMNumberField(s(.llmUIPriority), value: $model.draft.priority, valid: { _ in true }) { mark("priority", $0) }
                    Text(s(.llmUIPriorityHelp)).font(.caption).foregroundStyle(.secondary)
                    Toggle(s(.llmUIExcludeRotation), isOn: $model.draft.poolExclude)
                    Text(s(.llmUIExcludeHelp)).font(.caption).foregroundStyle(.secondary)
                    Toggle(s(.llmUIStreaming), isOn: $model.draft.streaming)
                    Text(s(.llmUIStreamingHelp)).font(.caption).foregroundStyle(.secondary)
                    LLMNumberField(s(.llmUIMaxTokens), value: $model.draft.maxTokens, valid: { $0 >= 0 }) { mark("tokens", $0) }
                    Text(s(.llmUIMaxTokensHelp)).font(.caption).foregroundStyle(.secondary)
                    Picker(s(.llmUIMaxTokensField), selection: $model.draft.maxTokensField) {
                        Text(s(.llmUIDefaultMaxTokens)).tag("")
                        Text("max_completion_tokens").tag("max_completion_tokens")
                    }.disabled(model.draft.format != .openai)
                }
                Section(s(.llmUIThinking)) {
                    Picker(s(.llmUIThinkingSwitch), selection: $model.draft.thinkingType) {
                        Text(s(.llmUIOmit)).tag(""); Text(s(.llmUIDisabled)).tag("disabled"); Text(s(.llmUIEnabled)).tag("enabled")
                    }
                    Picker(s(.llmUIEffort), selection: $model.draft.reasoningEffort) {
                        Text(s(.llmUIOmit)).tag("")
                        ForEach(["low", "medium", "high", "xhigh", "max"], id: \.self) { Text($0).tag($0) }
                    }
                    Text(s(.llmUIThinkingHelp)).font(.caption).foregroundStyle(.secondary)
                }
                Section(s(.llmUIProfileRetry)) {
                    LLMRetryRuleFields(title: s(.llmUIConnection), detail: s(.llmUIConnectDetail), rule: $model.draft.retry.connect) { mark("connect." + $0, $1) }
                    LLMRetryRuleFields(title: s(.llmUIEmpty), detail: s(.llmUIEmptyDetail), rule: $model.draft.retry.empty) { mark("empty." + $0, $1) }
                    LLMRetryRuleFields(title: s(.llmUIStream), detail: s(.llmUIStreamDetail), rule: $model.draft.retry.stream) { mark("stream." + $0, $1) }
                }
            }.formStyle(.grouped).disabled(busy)
            VStack(alignment: .leading, spacing: 10) {
                LLMRecoveryView(store: store)
                if let error = model.failure { Text(error.text(language: language)).foregroundStyle(.red).textSelection(.enabled) }
                if let result = model.testResult {
                    Text(f(.llmUITestSuccess, ["model": result.model ?? model.draft.model, "latency": (result.latencyMs ?? 0).formatted(.number.precision(.fractionLength(0)))])).foregroundStyle(.green)
                    if let reply = result.reply { Text(reply).font(.caption).lineLimit(5).textSelection(.enabled) }
                }
                HStack {
                    Button(s(.llmUIClose)) { model.close(); dismiss() }.keyboardShortcut(.cancelAction).disabled(model.isSaving || store.isMutating)
                    Spacer()
                    if busy { ProgressView().controlSize(.small) }
                    Button(s(.llmUITest)) { model.testConnection() }.disabled(busy || !model.invalidFields.isEmpty)
                    Button(s(.llmUISave)) { model.save() }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                        .disabled(busy || store.unknownRevision != nil || !model.invalidFields.isEmpty || model.draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.draft.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }.padding(20)
        }
        .frame(width: 680, height: 780)
        .interactiveDismissDisabled(model.isSaving || store.isMutating)
        .onAppear { model.activate() }
        .onChange(of: model.didSave) { _, saved in
            if saved, model.isActive { model.close(); dismiss() }
        }
        .onDisappear { model.close() }
    }
    private func mark(_ field: String, _ valid: Bool) { model.mark(field, valid) }
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
