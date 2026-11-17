import NetworkPNTRCore
import SwiftUI

private struct CreationChoice<ID: Hashable>: Identifiable { let id: ID; let title: String }

@MainActor struct TaskCreateSelectors: View {
    let model: TaskCreationModel
    let contextID: UUID
    @Environment(\.locale) private var locale
    private var language: AppLanguage { .preferred(in: [locale.identifier]) }
    private func s(_ key: AppStringKey) -> String { AppStrings.text(key, language: language) }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if model.context?.id == contextID {
                TaskCreateChoiceSection(model: model, contextID: contextID, title: .taskCreateProfiles,
                                        choices: (model.profiles.value ?? []).map { CreationChoice(id: $0.id, title: $0.name + " · " + $0.model) },
                                        key: \.draft.llmProfileIds, maximum: Int.max, failure: model.profiles.failure)
                if model.form.draft.llmProfileIds.isEmpty { Text(s(.taskCreateDefaultProfile)).font(.caption).foregroundStyle(.secondary) }
                ForEach(model.form.draft.llmProfileIds, id: \.self) { id in
                    HStack {
                        Text(model.profiles.value?.first(where: { $0.id == id })?.name ?? AppStrings.formatted(.taskCreateUnavailable, language: language, values: ["id": String(id)]))
                        Spacer()
                        Button(s(.taskCreateMoveUp), systemImage: "arrow.up") { model.moveProfile(id: id, offset: -1, contextID: contextID) }.disabled(model.form.draft.llmProfileIds.first == id)
                        Button(s(.taskCreateMoveDown), systemImage: "arrow.down") { model.moveProfile(id: id, offset: 1, contextID: contextID) }.disabled(model.form.draft.llmProfileIds.last == id)
                    }.labelStyle(.iconOnly)
                }
                TaskCreateChoiceSection(model: model, contextID: contextID, title: .taskCreateSources,
                                        choices: (model.sources.value ?? []).map { CreationChoice(id: $0.id, title: $0.name.isEmpty ? AppStrings.formatted(.taskUIUnnamed, language: language, values: ["id": $0.id]) : $0.name) },
                                        key: \.draft.sourceTaskIds, maximum: 8, failure: model.sources.failure)
                TaskCreateChoiceSection(model: model, contextID: contextID, title: .taskCreateCompanies,
                                        choices: (model.companies.value ?? []).map { CreationChoice(id: $0.id, title: $0.name) },
                                        key: \.draft.companyIds, maximum: 32, failure: model.companies.failure)
            }
        }
    }
}

@MainActor private struct TaskCreateChoiceSection<ID: Hashable>: View {
    let model: TaskCreationModel
    let contextID: UUID
    let title: AppStringKey
    let choices: [CreationChoice<ID>]
    let key: WritableKeyPath<TaskCreationForm, [ID]>
    let maximum: Int
    let failure: AppErrorMessage?
    @Environment(\.locale) private var locale
    private var language: AppLanguage { .preferred(in: [locale.identifier]) }
    private var selection: [ID] { TaskCreationBindings.field(model: model, contextID: contextID, key: key, fallback: []).wrappedValue }
    private var rows: [CreationChoice<ID>] {
        let known = Set(choices.map(\.id))
        return choices + selection.filter { !known.contains($0) }.map { CreationChoice(id: $0, title: AppStrings.formatted(.taskCreateUnavailable, language: language, values: ["id": String(describing: $0)])) }
    }
    var body: some View {
        GroupBox(AppStrings.text(title, language: language)) {
            VStack(alignment: .leading, spacing: 5) {
                if let failure { Text(failure.text(language: language)).foregroundStyle(.red).font(.caption) }
                if rows.isEmpty { Text(AppStrings.text(.taskCreateEmptyChoices, language: language)).foregroundStyle(.secondary).font(.caption) }
                else {
                    ScrollView {
                        LazyVStack(alignment: .leading) {
                            ForEach(rows) { choice in
                                Toggle(choice.title, isOn: Binding(get: { selection.contains(choice.id) }, set: {
                                    model.setSelected(key, value: choice.id, selected: $0, maximum: maximum, contextID: contextID)
                                })).disabled(!selection.contains(choice.id) && selection.count >= maximum)
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }.frame(height: min(140, CGFloat(rows.count) * 28))
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
