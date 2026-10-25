import ArtexCore
import SwiftUI

@MainActor struct TaskCreateView: View {
    let model: TaskCreationModel
    let contextID: UUID
    @Environment(\.locale) private var locale
    private var language: AppLanguage { .preferred(in: [locale.identifier]) }
    private func s(_ key: AppStringKey) -> String { AppStrings.text(key, language: language) }
    private func field<Value>(_ key: WritableKeyPath<TaskCreationForm, Value>, _ fallback: Value) -> Binding<Value> {
        TaskCreationBindings.field(model: model, contextID: contextID, key: key, fallback: fallback)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if model.context?.id == contextID {
                HStack {
                    VStack(alignment: .leading, spacing: 4) { Text(s(.taskCreateTitle)).font(.title2.bold()); Text(s(.taskCreateHelp)).foregroundStyle(.secondary) }
                    Spacer()
                    if model.isLoading { ProgressView().controlSize(.small) }
                    Button(s(.taskCreateOptionsRefresh), systemImage: "arrow.clockwise") { Task { await model.load(contextID: contextID) } }
                        .disabled(model.isLoading || model.isSubmitting)
                }
                Divider()
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        templatePicker
                        LabeledContent(s(.taskUIName)) { TextField(s(.taskUIName), text: field(\.draft.name, "")).textFieldStyle(.roundedBorder) }
                        categoryPicker
                        VStack(alignment: .leading) { Text(s(.taskUIDescription)).font(.headline); TextEditor(text: field(\.draft.description, "")).frame(minHeight: 90).border(.quaternary) }
                        VStack(alignment: .leading) { Text(s(.taskUIGoal)).font(.headline); TextEditor(text: field(\.draft.goal, "")).frame(minHeight: 90).border(.quaternary) }
                        TaskCreateSelectors(model: model, contextID: contextID)
                        TaskCreateRules(model: model, contextID: contextID)
                        DisclosureGroup(s(.taskCreateAdvanced)) {
                            VStack(alignment: .leading, spacing: 12) {
                                LabeledContent(s(.taskCreateTimeout)) { TextField("0", text: field(\.timeoutMinutes, "")).frame(width: 100).textFieldStyle(.roundedBorder) }
                                LabeledContent(s(.taskCreateHeartbeat)) { TextField("10", text: field(\.heartbeatMinutes, "10")).frame(width: 100).textFieldStyle(.roundedBorder) }
                                Toggle(s(.taskCreateSeed), isOn: field(\.draft.seedFirstIntent, false))
                                Toggle(s(.taskCreateCoverage), isOn: field(\.draft.coverageEnabled, true))
                            }.padding(.top, 10)
                        }
                    }.padding(.vertical, 6)
                }.disabled(model.isSubmitting || model.uncertain)
                if model.uncertain { Text(s(.taskUIUncertain)).foregroundStyle(.orange) }
                else if let failure = model.failure { Text(failure.text(language: language)).foregroundStyle(.red) }
                Divider()
                HStack {
                    Button(s(.taskCreateDiscard)) { model.discard(contextID: contextID) }.help(s(.taskCreateDiscardHelp)).disabled(model.isSubmitting)
                    Spacer()
                    if model.isSubmitting { ProgressView().controlSize(.small) }
                    Button(s(model.uncertain ? .taskUIClose : .taskUICancel)) { model.close(contextID: contextID) }.keyboardShortcut(.cancelAction).disabled(model.isSubmitting)
                    Button(s(.taskCreateCreate)) { Task { _ = await model.submit(contextID: contextID) } }
                        .keyboardShortcut(.defaultAction).disabled(model.isSubmitting || model.isLoading || model.uncertain)
                }
            }
        }.padding(20).frame(width: 640, height: 600)
        .interactiveDismissDisabled(model.isSubmitting)
        .task { await model.load(contextID: contextID) }
    }
    private var templatePicker: some View {
        VStack(alignment: .leading) {
            Picker(s(.taskCreateTemplate), selection: Binding(get: { model.context?.id == contextID ? model.selectedTemplateID ?? 0 : 0 }, set: { model.chooseTemplate($0 == 0 ? nil : $0, contextID: contextID) })) {
                Text(s(.taskCreateNoTemplate)).tag(Int64(0))
                ForEach(model.templates.value ?? []) { Text($0.name).tag($0.id) }
                if let id = model.selectedTemplateID, !(model.templates.value ?? []).contains(where: { $0.id == id }) { Text(unavailable(id)).tag(id) }
            }
            if let error = model.templates.failure { Text(error.text(language: language)).font(.caption).foregroundStyle(.red) }
        }
    }
    private var categoryPicker: some View {
        VStack(alignment: .leading) {
            Picker(s(.taskUICategory), selection: Binding(get: { field(\.draft.categoryId, nil).wrappedValue ?? 0 }, set: { model.update(\.draft.categoryId, value: $0 == 0 ? nil : $0, contextID: contextID) })) {
                Text(s(.taskUIUncategorized)).tag(Int64(0))
                ForEach(model.categories.value ?? []) { Text($0.name).tag($0.id) }
                if let id = model.form.draft.categoryId, !(model.categories.value ?? []).contains(where: { $0.id == id }) { Text(unavailable(id)).tag(id) }
            }
            if let error = model.categories.failure { Text(error.text(language: language)).font(.caption).foregroundStyle(.red) }
        }
    }
    private func unavailable(_ id: Int64) -> String { AppStrings.formatted(.taskCreateUnavailable, language: language, values: ["id": String(id)]) }
}
